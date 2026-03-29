const test = require('node:test');
const assert = require('node:assert/strict');

const {
    CARD_KINDS,
    ERROR_CODES,
    createInitialState,
    validateMove,
    applyMove,
    drawCard,
    resolveChallenge,
    autoActionOnTimeout,
    serializePublicState,
    serializePrivateState
} = require('../src/services/colorClashRulesEngine');

const makePlayers = (count) => Array.from({ length: count }, (_, seatIndex) => ({
    seatIndex,
    userId: `user-${seatIndex}`
}));

const collectAllCards = (state) => [
    ...Object.values(state.handsBySeat).flat(),
    ...state.drawPile,
    ...state.discardPile
];

const matchesCardSpec = (card, spec) => {
    if (spec.id && card.id !== spec.id) return false;
    if (spec.kind && card.kind !== spec.kind) return false;
    if (Object.prototype.hasOwnProperty.call(spec, 'hue') && card.hue !== spec.hue) return false;
    if (Object.prototype.hasOwnProperty.call(spec, 'value') && card.value !== spec.value) return false;
    return true;
};

const snapshotPublic = (state) => {
    const publicState = serializePublicState({ state });
    return {
        phase: publicState.phase,
        currentTurnSeat: publicState.currentTurnSeat,
        direction: publicState.direction,
        currentHue: publicState.currentHue,
        discardTop: publicState.discardTop,
        pendingEffect: publicState.pendingEffect,
        players: publicState.players.map((player) => ({
            seatIndex: player.seatIndex,
            handCount: player.handCount,
            timeoutStrikes: player.timeoutStrikes,
            hasShield: player.hasShield,
            pendingLastCardCall: player.pendingLastCardCall,
            status: player.status
        })),
        roundResult: publicState.roundResult
    };
};

const finalizeScenario = (state, options = {}) => {
    state.phase = 'active';
    state.roundResult = null;
    state.discardTop = state.discardPile[state.discardPile.length - 1];
    for (const player of state.players) {
        const hand = state.handsBySeat[String(player.seatIndex)] || [];
        player.handCount = hand.length;
        if (hand.length !== 1) {
            player.pendingLastCardCall = false;
            player.declaredLastCard = false;
        }
        if (!player.statusEffects) {
            player.statusEffects = { shield: false };
        }
    }
    if (options.turnContext) {
        state.turnContext = options.turnContext;
    } else {
        state.turnContext = { phase: 'main', drawnCardId: null };
    }
    return state;
};

const buildScenario = ({
    playersCount = 3,
    customCards = {},
    handSpecs = {},
    discardSpec,
    drawSpecs = [],
    currentTurnSeat = 0,
    currentHue,
    direction = 1,
    pendingEffect = null,
    turnContext = null,
    playerTweaks = {}
}) => {
    const { state } = createInitialState({
        players: makePlayers(playersCount),
        rulesConfig: { customCards },
        shuffleSeed: `scenario-${playersCount}-${JSON.stringify(customCards)}`,
        roundNumber: 1
    });

    const pool = collectAllCards(state);
    const takeCard = (spec, label) => {
        const index = pool.findIndex((card) => matchesCardSpec(card, spec));
        assert.notEqual(index, -1, `Unable to find card for ${label || JSON.stringify(spec)}`);
        return pool.splice(index, 1)[0];
    };

    const handsBySeat = {};
    for (let seatIndex = 0; seatIndex < playersCount; seatIndex += 1) {
        const seatSpecs = handSpecs[seatIndex] || [];
        handsBySeat[String(seatIndex)] = seatSpecs.map((spec, index) =>
            takeCard(spec, `seat ${seatIndex} hand ${index}`));
    }

    const discardCard = takeCard(discardSpec, 'discard');
    const seededDraw = drawSpecs.map((spec, index) => takeCard(spec, `draw ${index}`));

    state.handsBySeat = handsBySeat;
    state.discardPile = [discardCard];
    state.drawPile = seededDraw.concat(pool);
    state.currentTurnSeat = currentTurnSeat;
    state.currentHue = currentHue ?? discardCard.hue;
    state.direction = direction;
    state.pendingEffect = pendingEffect ? structuredClone(pendingEffect) : null;
    state.players = state.players.map((player) => ({
        ...player,
        status: 'active',
        timeoutStrikes: 0,
        pendingLastCardCall: false,
        declaredLastCard: false,
        statusEffects: { shield: false },
        ...(playerTweaks[player.seatIndex] || {})
    }));

    return finalizeScenario(state, { turnContext });
};

test('createInitialState uses deterministic seeded shuffle', () => {
    const players = makePlayers(4);
    const first = createInitialState({
        players,
        rulesConfig: { customCards: { shield: true, echo: true, swap: true } },
        shuffleSeed: 'seed-alpha',
        roundNumber: 2
    });
    const second = createInitialState({
        players,
        rulesConfig: { customCards: { shield: true, echo: true, swap: true } },
        shuffleSeed: 'seed-alpha',
        roundNumber: 2
    });
    const third = createInitialState({
        players,
        rulesConfig: { customCards: { shield: true, echo: true, swap: true } },
        shuffleSeed: 'seed-beta',
        roundNumber: 2
    });

    assert.deepStrictEqual(first.state.handsBySeat, second.state.handsBySeat);
    assert.deepStrictEqual(first.state.discardPile, second.state.discardPile);
    assert.notDeepStrictEqual(
        first.state.handsBySeat['0'].map((card) => card.id),
        third.state.handsBySeat['0'].map((card) => card.id)
    );
});

test('serializePublicState never leaks hands or draw order', () => {
    const { state } = createInitialState({
        players: makePlayers(3),
        rulesConfig: {},
        shuffleSeed: 'public-state',
        roundNumber: 1
    });

    const publicState = serializePublicState({ state });
    const privateState = serializePrivateState({ state, seatIndex: 0 });
    const publicJson = JSON.stringify(publicState);

    assert.equal(publicState.players[0].handCount, privateState.hand.length);
    assert.equal(Object.prototype.hasOwnProperty.call(publicState, 'handsBySeat'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(publicState, 'drawPile'), false);
    assert.equal(publicJson.includes(privateState.hand[0].id), false);
});

test('Freeze skips the next player and matches snapshot', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [
                { kind: CARD_KINDS.FREEZE, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 3 }]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 },
        currentTurnSeat: 0
    });

    const freezeCard = state.handsBySeat['0'][0];
    const result = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: freezeCard.id }
    });

    assert.deepStrictEqual(snapshotPublic(result.nextState), {
        phase: 'active',
        currentTurnSeat: 2,
        direction: 1,
        currentHue: 'ember',
        discardTop: {
            id: freezeCard.id,
            kind: 'freeze',
            hue: 'ember',
            value: null
        },
        pendingEffect: null,
        players: [
            { seatIndex: 0, handCount: 1, timeoutStrikes: 0, hasShield: false, pendingLastCardCall: true, status: 'active' },
            { seatIndex: 1, handCount: 1, timeoutStrikes: 0, hasShield: false, pendingLastCardCall: false, status: 'active' },
            { seatIndex: 2, handCount: 1, timeoutStrikes: 0, hasShield: false, pendingLastCardCall: false, status: 'active' }
        ],
        roundResult: null
    });
});

test('Flip Flow reverses direction and hands turn to the previous seat', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [
                { kind: CARD_KINDS.FLIP_FLOW, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 3 }]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 },
        currentTurnSeat: 0
    });

    const flipCard = state.handsBySeat['0'][0];
    const result = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: flipCard.id }
    });

    assert.equal(result.nextState.direction, -1);
    assert.equal(result.nextState.currentTurnSeat, 2);
});

test('Pulse +2 stacking forces the next target to draw the full stack', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [
                { kind: CARD_KINDS.PULSE_PLUS_TWO, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [
                { kind: CARD_KINDS.PULSE_PLUS_TWO, hue: 'grove' },
                { kind: CARD_KINDS.NUMBER, hue: 'solar', value: 2 }
            ],
            2: [
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 3 },
                { kind: CARD_KINDS.NUMBER, hue: 'solar', value: 4 }
            ]
        },
        drawSpecs: [
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 7 },
            { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 8 },
            { kind: CARD_KINDS.NUMBER, hue: 'solar', value: 9 },
            { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 6 }
        ],
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 }
    });

    const firstPulse = state.handsBySeat['0'][0];
    const stepOne = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: firstPulse.id }
    });
    assert.equal(stepOne.nextState.pendingEffect.amount, 2);
    assert.equal(stepOne.nextState.currentTurnSeat, 1);

    const secondPulse = stepOne.nextState.handsBySeat['1'][0];
    const stepTwo = applyMove({
        state: stepOne.nextState,
        actorSeat: 1,
        move: { type: 'play_card', cardId: secondPulse.id }
    });
    assert.equal(stepTwo.nextState.pendingEffect.amount, 4);
    assert.equal(stepTwo.nextState.currentTurnSeat, 2);

    const penalty = applyMove({
        state: stepTwo.nextState,
        actorSeat: 2,
        move: { type: 'draw_card' }
    });

    assert.equal(penalty.nextState.handsBySeat['2'].length, 6);
    assert.equal(penalty.nextState.currentTurnSeat, 0);
    assert.equal(penalty.nextState.pendingEffect, null);
});

test('Prism changes the active hue without leaking private state', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [
                { kind: CARD_KINDS.PRISM },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 3 }]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 }
    });

    const prism = state.handsBySeat['0'][0];
    const result = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: prism.id, chosenHue: 'solar' }
    });

    assert.equal(result.nextState.currentHue, 'solar');
    assert.equal(result.nextState.currentTurnSeat, 1);
    assert.equal(
        JSON.stringify(serializePublicState({ state: result.nextState })).includes(result.nextState.drawPile[0].id),
        false
    );
});

test('Prism Surge challenge succeeds when the offender had a legal non-prism alternative', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [
                { kind: CARD_KINDS.PRISM_SURGE },
                { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 1 },
                { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }
            ],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'tide', value: 3 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 4 }]
        },
        drawSpecs: [
            { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 5 },
            { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 6 },
            { kind: CARD_KINDS.NUMBER, hue: 'solar', value: 7 },
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 8 }
        ],
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 9 }
    });

    const surge = state.handsBySeat['0'][0];
    const afterSurge = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: surge.id, chosenHue: 'solar' }
    });

    const validation = validateMove({
        state: afterSurge.nextState,
        actorSeat: 1,
        move: { type: 'challenge' }
    });
    assert.equal(validation.ok, true);

    const challenged = resolveChallenge({
        state: afterSurge.nextState,
        challengerSeat: 1,
        decision: 'challenge'
    });

    assert.equal(challenged.nextState.currentTurnSeat, 1);
    assert.equal(challenged.nextState.handsBySeat['0'].length, 6);
    assert.equal(challenged.nextState.pendingEffect, null);
});

test('Prism Surge challenge fails when there was no legal alternative', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [
                { kind: CARD_KINDS.PRISM_SURGE },
                { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }
            ],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'tide', value: 3 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 4 }]
        },
        drawSpecs: [
            { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 5 },
            { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 6 },
            { kind: CARD_KINDS.NUMBER, hue: 'solar', value: 7 },
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 8 },
            { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 },
            { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 1 }
        ],
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 9 }
    });

    const surge = state.handsBySeat['0'][0];
    const afterSurge = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: surge.id, chosenHue: 'solar' }
    });
    const challenged = resolveChallenge({
        state: afterSurge.nextState,
        challengerSeat: 1,
        decision: 'challenge'
    });

    assert.equal(challenged.nextState.handsBySeat['1'].length, 7);
    assert.equal(challenged.nextState.currentTurnSeat, 2);
});

test('Shield blocks the next incoming Pulse +2 penalty', () => {
    const state = buildScenario({
        playersCount: 2,
        customCards: { shield: true },
        handSpecs: {
            0: [
                { kind: CARD_KINDS.SHIELD, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [
                { kind: CARD_KINDS.PULSE_PLUS_TWO, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }
            ]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 }
    });

    const shield = state.handsBySeat['0'][0];
    const afterShield = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: shield.id }
    });
    assert.equal(afterShield.nextState.players[0].statusEffects.shield, true);

    const pulse = afterShield.nextState.handsBySeat['1'][0];
    const afterPulse = applyMove({
        state: afterShield.nextState,
        actorSeat: 1,
        move: { type: 'play_card', cardId: pulse.id }
    });

    assert.equal(afterPulse.nextState.players[0].statusEffects.shield, false);
    assert.equal(afterPulse.nextState.currentTurnSeat, 0);
    assert.equal(afterPulse.nextState.pendingEffect, null);
    assert.equal(afterPulse.nextState.handsBySeat['0'].length, 1);
});

test('Echo repeats the previous Pulse +2 effect', () => {
    const state = buildScenario({
        playersCount: 3,
        customCards: { echo: true },
        handSpecs: {
            0: [
                { kind: CARD_KINDS.ECHO, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 3 }]
        },
        discardSpec: { kind: CARD_KINDS.PULSE_PLUS_TWO, hue: 'ember' }
    });

    const echo = state.handsBySeat['0'][0];
    const result = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: echo.id }
    });

    assert.equal(result.nextState.pendingEffect.kind, 'pulse_stack');
    assert.equal(result.nextState.pendingEffect.amount, 2);
    assert.equal(result.nextState.currentTurnSeat, 1);
});

test('Swap exchanges hands with the chosen target seat', () => {
    const state = buildScenario({
        playersCount: 2,
        customCards: { swap: true },
        handSpecs: {
            0: [
                { kind: CARD_KINDS.SWAP, hue: 'ember' },
                { kind: CARD_KINDS.NUMBER, hue: 'tide', value: 1 }
            ],
            1: [
                { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 },
                { kind: CARD_KINDS.NUMBER, hue: 'solar', value: 3 }
            ]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 }
    });

    const swapCard = state.handsBySeat['0'][0];
    const result = applyMove({
        state,
        actorSeat: 0,
        move: { type: 'play_card', cardId: swapCard.id, targetSeat: 1 }
    });

    assert.deepStrictEqual(
        result.nextState.handsBySeat['0'].map((card) => card.id).sort(),
        state.handsBySeat['1'].map((card) => card.id).sort()
    );
});

test('drawCard reshuffles discard without leaking the top discard', () => {
    const state = buildScenario({
        playersCount: 2,
        handSpecs: {
            0: [{ kind: CARD_KINDS.NUMBER, hue: 'ember', value: 1 }],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'tide', value: 2 }]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'grove', value: 3 },
        drawSpecs: []
    });

    const originalTopDiscardId = state.discardPile[state.discardPile.length - 1].id;
    state.discardPile = state.drawPile.splice(0, state.drawPile.length).concat(state.discardPile);
    state.drawPile = [];
    finalizeScenario(state);

    const result = drawCard({
        state,
        actorSeat: 0,
        count: 1,
        reason: 'reshuffle_test'
    });

    assert.ok(result.events.some((event) => event.type === 'reshuffle'));
    assert.equal(result.nextState.discardPile[result.nextState.discardPile.length - 1].id, originalTopDiscardId);
});

test('autoActionOnTimeout declines challenge automatically', () => {
    const state = buildScenario({
        playersCount: 3,
        handSpecs: {
            0: [{ kind: CARD_KINDS.NUMBER, hue: 'grove', value: 2 }],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'tide', value: 3 }],
            2: [{ kind: CARD_KINDS.NUMBER, hue: 'solar', value: 4 }]
        },
        drawSpecs: [
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 1 },
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 2 },
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 3 },
            { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 4 }
        ],
        discardSpec: { kind: CARD_KINDS.PRISM_SURGE },
        currentTurnSeat: 1,
        currentHue: 'solar',
        pendingEffect: {
            kind: 'prism_surge_challenge',
            sourceSeat: 0,
            targetSeat: 1,
            amount: 4,
            chosenHue: 'solar',
            originalTopCard: { kind: 'number', hue: 'ember', value: 9 },
            offenderHadPlayableAlternative: false
        },
        turnContext: { phase: 'challenge_response', drawnCardId: null }
    });

    const result = autoActionOnTimeout({ state });

    assert.equal(result.nextState.handsBySeat['1'].length, 5);
    assert.equal(result.nextState.currentTurnSeat, 2);
});

test('autoActionOnTimeout forfeits after repeated strikes', () => {
    const state = buildScenario({
        playersCount: 2,
        handSpecs: {
            0: [{ kind: CARD_KINDS.NUMBER, hue: 'ember', value: 1 }],
            1: [{ kind: CARD_KINDS.NUMBER, hue: 'tide', value: 2 }]
        },
        discardSpec: { kind: CARD_KINDS.NUMBER, hue: 'ember', value: 5 },
        playerTweaks: {
            0: { timeoutStrikes: 2 }
        }
    });
    state.rulesConfig.timeoutStrikeLimit = 3;

    const result = autoActionOnTimeout({ state });

    assert.equal(result.nextState.phase, 'completed');
    assert.equal(result.nextState.players[0].status, 'forfeited');
    assert.equal(result.nextState.roundResult.winnerSeat, 1);
});
