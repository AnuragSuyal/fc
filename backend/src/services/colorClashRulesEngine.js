const GAME_ID = 'color_clash';

const DEFAULT_HUES = Object.freeze(['ember', 'tide', 'grove', 'solar']);
const DEFAULT_RULES = Object.freeze({
    startingHandSize: 7,
    timeoutStrikeLimit: 3,
    challengePenaltyBonus: 2,
    hues: DEFAULT_HUES,
    customCards: {
        shield: false,
        echo: false,
        swap: false
    }
});

const CARD_KINDS = Object.freeze({
    NUMBER: 'number',
    FREEZE: 'freeze',
    FLIP_FLOW: 'flip_flow',
    PULSE_PLUS_TWO: 'pulse_plus_two',
    PRISM: 'prism',
    PRISM_SURGE: 'prism_surge',
    SHIELD: 'shield',
    ECHO: 'echo',
    SWAP: 'swap'
});

const MOVE_TYPES = Object.freeze({
    PLAY_CARD: 'play_card',
    DRAW_CARD: 'draw_card',
    KEEP_DRAWN: 'keep_drawn',
    CHALLENGE: 'challenge',
    DECLINE_CHALLENGE: 'decline_challenge'
});

const ERROR_CODES = Object.freeze({
    INVALID_PLAYERS: 'INVALID_PLAYERS',
    DUPLICATE_SEAT: 'DUPLICATE_SEAT',
    ROUND_NOT_ACTIVE: 'ROUND_NOT_ACTIVE',
    INVALID_TURN: 'INVALID_TURN',
    MOVE_TYPE_REQUIRED: 'MOVE_TYPE_REQUIRED',
    UNKNOWN_MOVE_TYPE: 'UNKNOWN_MOVE_TYPE',
    CARD_ID_REQUIRED: 'CARD_ID_REQUIRED',
    CARD_NOT_FOUND: 'CARD_NOT_FOUND',
    CARD_NOT_PLAYABLE: 'CARD_NOT_PLAYABLE',
    ONLY_DRAWN_CARD_PLAYABLE: 'ONLY_DRAWN_CARD_PLAYABLE',
    DRAW_ALREADY_PERFORMED: 'DRAW_ALREADY_PERFORMED',
    KEEP_DRAWN_NOT_AVAILABLE: 'KEEP_DRAWN_NOT_AVAILABLE',
    CHALLENGE_NOT_AVAILABLE: 'CHALLENGE_NOT_AVAILABLE',
    CHALLENGE_RESPONSE_REQUIRED: 'CHALLENGE_RESPONSE_REQUIRED',
    STACK_RESPONSE_REQUIRED: 'STACK_RESPONSE_REQUIRED',
    HUE_REQUIRED: 'HUE_REQUIRED',
    INVALID_HUE: 'INVALID_HUE',
    TARGET_REQUIRED: 'TARGET_REQUIRED',
    INVALID_TARGET: 'INVALID_TARGET',
    INTERNAL_INVALID_STATE: 'INTERNAL_INVALID_STATE'
});

const PENDING_EFFECTS = Object.freeze({
    FREEZE: 'freeze',
    PULSE_STACK: 'pulse_stack',
    PRISM_SURGE_CHALLENGE: 'prism_surge_challenge'
});

const cloneValue = (value) => {
    if (typeof structuredClone === 'function') {
        return structuredClone(value);
    }
    return JSON.parse(JSON.stringify(value));
};

const stableCardView = (card) => ({
    id: card.id,
    kind: card.kind,
    hue: card.hue ?? null,
    value: typeof card.value === 'number' ? card.value : null
});

const createSeedHasher = (seed) => {
    const text = String(seed ?? '0');
    let hash = 1779033703 ^ text.length;
    for (let index = 0; index < text.length; index += 1) {
        hash = Math.imul(hash ^ text.charCodeAt(index), 3432918353);
        hash = (hash << 13) | (hash >>> 19);
    }
    return () => {
        hash = Math.imul(hash ^ (hash >>> 16), 2246822507);
        hash = Math.imul(hash ^ (hash >>> 13), 3266489909);
        return (hash ^= hash >>> 16) >>> 0;
    };
};

const createSeededRandom = (seed) => {
    const seedHash = createSeedHasher(seed)();
    let value = seedHash >>> 0;
    return () => {
        value += 0x6D2B79F5;
        let temp = value;
        temp = Math.imul(temp ^ (temp >>> 15), temp | 1);
        temp ^= temp + Math.imul(temp ^ (temp >>> 7), temp | 61);
        return ((temp ^ (temp >>> 14)) >>> 0) / 4294967296;
    };
};

const shuffleDeterministic = (items, seed) => {
    const random = createSeededRandom(seed);
    const output = items.slice();
    for (let index = output.length - 1; index > 0; index -= 1) {
        const swapIndex = Math.floor(random() * (index + 1));
        [output[index], output[swapIndex]] = [output[swapIndex], output[index]];
    }
    return output;
};

const sortPlayers = (players) => players
    .map((player) => ({ ...player }))
    .sort((left, right) => left.seatIndex - right.seatIndex);

const normalizeRulesConfig = (rulesConfig = {}) => {
    const normalized = cloneValue(DEFAULT_RULES);
    normalized.startingHandSize = Number.isInteger(rulesConfig.startingHandSize)
        ? rulesConfig.startingHandSize
        : DEFAULT_RULES.startingHandSize;
    normalized.timeoutStrikeLimit = Number.isInteger(rulesConfig.timeoutStrikeLimit)
        ? rulesConfig.timeoutStrikeLimit
        : DEFAULT_RULES.timeoutStrikeLimit;
    normalized.challengePenaltyBonus = Number.isInteger(rulesConfig.challengePenaltyBonus)
        ? rulesConfig.challengePenaltyBonus
        : DEFAULT_RULES.challengePenaltyBonus;
    normalized.hues = Array.isArray(rulesConfig.hues) && rulesConfig.hues.length >= 4
        ? rulesConfig.hues.map((hue) => String(hue).trim().toLowerCase())
        : DEFAULT_HUES.slice();
    normalized.customCards = {
        shield: Boolean(rulesConfig?.customCards?.shield),
        echo: Boolean(rulesConfig?.customCards?.echo),
        swap: Boolean(rulesConfig?.customCards?.swap)
    };
    return normalized;
};

const buildDeck = (rulesConfig) => {
    const deck = [];
    const counters = new Map();

    const nextId = (kind, hue, value) => {
        const counterKey = `${kind}:${hue ?? 'neutral'}:${value ?? 'none'}`;
        const nextCount = (counters.get(counterKey) || 0) + 1;
        counters.set(counterKey, nextCount);
        return `${kind}:${hue ?? 'neutral'}:${value ?? 'none'}:${nextCount}`;
    };

    const pushCard = (kind, hue = null, value = null) => {
        deck.push({
            id: nextId(kind, hue, value),
            kind,
            hue,
            value
        });
    };

    for (const hue of rulesConfig.hues) {
        pushCard(CARD_KINDS.NUMBER, hue, 0);
        for (let value = 1; value <= 9; value += 1) {
            pushCard(CARD_KINDS.NUMBER, hue, value);
            pushCard(CARD_KINDS.NUMBER, hue, value);
        }
        for (let count = 0; count < 2; count += 1) {
            pushCard(CARD_KINDS.FREEZE, hue);
            pushCard(CARD_KINDS.FLIP_FLOW, hue);
            pushCard(CARD_KINDS.PULSE_PLUS_TWO, hue);
        }
        if (rulesConfig.customCards.shield) pushCard(CARD_KINDS.SHIELD, hue);
        if (rulesConfig.customCards.echo) pushCard(CARD_KINDS.ECHO, hue);
        if (rulesConfig.customCards.swap) pushCard(CARD_KINDS.SWAP, hue);
    }

    for (let count = 0; count < 4; count += 1) {
        pushCard(CARD_KINDS.PRISM);
        pushCard(CARD_KINDS.PRISM_SURGE);
    }

    return deck;
};

const getTopDiscard = (state) => state.discardPile[state.discardPile.length - 1] || null;

const getPlayerBySeat = (state, seatIndex) =>
    state.players.find((player) => player.seatIndex === seatIndex) || null;

const getHand = (state, seatIndex) => state.handsBySeat[String(seatIndex)] || [];

const setHand = (state, seatIndex, hand) => {
    state.handsBySeat[String(seatIndex)] = hand;
};

const activeSeatOrder = (state) => state.players
    .filter((player) => player.status !== 'forfeited')
    .map((player) => player.seatIndex)
    .sort((left, right) => left - right);

const nextActiveSeat = (state, fromSeat, steps = 1, direction = state.direction) => {
    const seats = activeSeatOrder(state);
    if (seats.length === 0) return fromSeat;
    if (seats.length === 1) return seats[0];
    let cursor = seats.indexOf(fromSeat);
    if (cursor === -1) {
        cursor = 0;
    }
    let remainingSteps = steps;
    while (remainingSteps > 0) {
        cursor = (cursor + direction + seats.length) % seats.length;
        remainingSteps -= 1;
    }
    return seats[cursor];
};

const syncDerivedState = (state) => {
    state.discardTop = getTopDiscard(state);
    for (const player of state.players) {
        const hand = getHand(state, player.seatIndex);
        player.handCount = hand.length;
        if (hand.length !== 1) {
            player.pendingLastCardCall = false;
            player.declaredLastCard = false;
        }
    }
};

const allZoneCards = (state) => [
    ...Object.values(state.handsBySeat).flat(),
    ...state.drawPile,
    ...state.discardPile
];

const assertStateInvariants = (state) => {
    if (!state || typeof state !== 'object') {
        throw new Error(ERROR_CODES.INTERNAL_INVALID_STATE);
    }

    const deckCards = allZoneCards(state);
    const seen = new Set();
    for (const card of deckCards) {
        if (!card || !card.id) {
            throw new Error(ERROR_CODES.INTERNAL_INVALID_STATE);
        }
        if (seen.has(card.id)) {
            throw new Error(`DUPLICATE_CARD:${card.id}`);
        }
        seen.add(card.id);
    }

    if (state.deckDefinition?.totalCards !== deckCards.length) {
        throw new Error('CARD_COUNT_MISMATCH');
    }

    const knownIds = new Set(state.deckDefinition?.allCardIds || []);
    if (knownIds.size !== deckCards.length) {
        throw new Error('FULL_DECK_DEFINITION_MISMATCH');
    }

    for (const card of deckCards) {
        if (!knownIds.has(card.id)) {
            throw new Error(`UNKNOWN_CARD:${card.id}`);
        }
    }

    const currentTurnPlayer = getPlayerBySeat(state, state.currentTurnSeat);
    if (!currentTurnPlayer) {
        throw new Error('MISSING_TURN_OWNER');
    }

    if (!state.discardPile.length) {
        throw new Error('EMPTY_DISCARD');
    }
};

const isPrismCard = (card) =>
    card.kind === CARD_KINDS.PRISM || card.kind === CARD_KINDS.PRISM_SURGE;

const canCardMatchTop = (card, state) => {
    const topCard = getTopDiscard(state);
    if (!topCard) return false;
    if (isPrismCard(card)) return true;
    if (card.hue && card.hue === state.currentHue) return true;

    if (card.kind === CARD_KINDS.NUMBER && topCard.kind === CARD_KINDS.NUMBER) {
        return card.value === topCard.value;
    }

    return card.kind === topCard.kind;
};

const hasAlternativePlayableCard = (state, seatIndex, excludedCardId) => {
    const hand = getHand(state, seatIndex);
    return hand.some((card) =>
        card.id !== excludedCardId &&
        !isPrismCard(card) &&
        canCardMatchTop(card, state)
    );
};

const validateHue = (rulesConfig, chosenHue) => rulesConfig.hues.includes(String(chosenHue || '').trim().toLowerCase());

const normalizeMove = (move = {}) => ({
    type: move?.type ? String(move.type).trim().toLowerCase() : '',
    cardId: move?.cardId ? String(move.cardId) : undefined,
    chosenHue: move?.chosenHue ? String(move.chosenHue).trim().toLowerCase() : undefined,
    targetSeat: Number.isInteger(move?.targetSeat) ? move.targetSeat : undefined,
    declareLastCard: Boolean(move?.declareLastCard)
});

const publicPendingEffect = (pendingEffect) => {
    if (!pendingEffect) return null;
    return {
        kind: pendingEffect.kind,
        sourceSeat: pendingEffect.sourceSeat,
        targetSeat: pendingEffect.targetSeat,
        amount: pendingEffect.amount ?? null,
        chosenHue: pendingEffect.chosenHue ?? null,
        challengeOpen: pendingEffect.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE
    };
};

const getLegalMoves = (state, seatIndex) => {
    const hand = getHand(state, seatIndex);
    const legalMoves = [];
    const currentPlayerTurn = state.currentTurnSeat === seatIndex;
    const pendingEffect = state.pendingEffect;

    if (pendingEffect?.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE) {
        if (pendingEffect.targetSeat === seatIndex) {
            legalMoves.push({ type: MOVE_TYPES.CHALLENGE });
            legalMoves.push({ type: MOVE_TYPES.DECLINE_CHALLENGE });
        }
        return legalMoves;
    }

    if (!currentPlayerTurn) {
        return legalMoves;
    }

    if (pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK && pendingEffect.targetSeat === seatIndex) {
        for (const card of hand) {
            if (card.kind === CARD_KINDS.PULSE_PLUS_TWO) {
                legalMoves.push({ type: MOVE_TYPES.PLAY_CARD, cardId: card.id });
            }
        }
        legalMoves.push({ type: MOVE_TYPES.DRAW_CARD });
        return legalMoves;
    }

    if (state.turnContext.phase === 'after_draw') {
        const drawnCardId = state.turnContext.drawnCardId;
        const drawnCard = hand.find((card) => card.id === drawnCardId);
        if (drawnCard && canCardMatchTop(drawnCard, state)) {
            const baseMove = { type: MOVE_TYPES.PLAY_CARD, cardId: drawnCard.id };
            if (isPrismCard(drawnCard)) {
                for (const hue of state.rulesConfig.hues) {
                    legalMoves.push({ ...baseMove, chosenHue: hue });
                }
            } else {
                legalMoves.push(baseMove);
            }
        }
        legalMoves.push({ type: MOVE_TYPES.KEEP_DRAWN });
        return legalMoves;
    }

    for (const card of hand) {
        if (!canCardMatchTop(card, state)) continue;

        if (card.kind === CARD_KINDS.PRISM || card.kind === CARD_KINDS.PRISM_SURGE) {
            for (const hue of state.rulesConfig.hues) {
                legalMoves.push({
                    type: MOVE_TYPES.PLAY_CARD,
                    cardId: card.id,
                    chosenHue: hue
                });
            }
            continue;
        }

        if (card.kind === CARD_KINDS.SWAP) {
            for (const player of state.players) {
                if (player.status === 'forfeited' || player.seatIndex === seatIndex) continue;
                legalMoves.push({
                    type: MOVE_TYPES.PLAY_CARD,
                    cardId: card.id,
                    targetSeat: player.seatIndex
                });
            }
            continue;
        }

        if (card.kind === CARD_KINDS.ECHO) {
            const previousTop = getTopDiscard(state);
            if (previousTop?.kind === CARD_KINDS.PRISM || previousTop?.kind === CARD_KINDS.PRISM_SURGE) {
                for (const hue of state.rulesConfig.hues) {
                    legalMoves.push({
                        type: MOVE_TYPES.PLAY_CARD,
                        cardId: card.id,
                        chosenHue: hue
                    });
                }
                continue;
            }
            if (previousTop?.kind === CARD_KINDS.SWAP) {
                for (const player of state.players) {
                    if (player.status === 'forfeited' || player.seatIndex === seatIndex) continue;
                    legalMoves.push({
                        type: MOVE_TYPES.PLAY_CARD,
                        cardId: card.id,
                        targetSeat: player.seatIndex
                    });
                }
                continue;
            }
        }

        legalMoves.push({
            type: MOVE_TYPES.PLAY_CARD,
            cardId: card.id
        });
    }

    legalMoves.push({ type: MOVE_TYPES.DRAW_CARD });
    return legalMoves;
};

const serializePublicState = ({ state }) => ({
    gameId: state.gameId,
    roundNumber: state.roundNumber,
    phase: state.phase,
    currentTurnSeat: state.currentTurnSeat,
    direction: state.direction,
    currentHue: state.currentHue,
    discardTop: stableCardView(getTopDiscard(state)),
    drawPileCount: state.drawPile.length,
    discardCount: state.discardPile.length,
    turnContext: {
        phase: state.turnContext.phase
    },
    pendingEffect: publicPendingEffect(state.pendingEffect),
    players: state.players
        .map((player) => ({
            seatIndex: player.seatIndex,
            userId: player.userId ?? null,
            status: player.status,
            handCount: player.handCount,
            timeoutStrikes: player.timeoutStrikes,
            hasShield: Boolean(player.statusEffects?.shield),
            pendingLastCardCall: Boolean(player.pendingLastCardCall),
            declaredLastCard: Boolean(player.declaredLastCard)
        }))
        .sort((left, right) => left.seatIndex - right.seatIndex),
    roundResult: state.roundResult || null
});

const serializePrivateState = ({ state, seatIndex }) => ({
    seatIndex,
    currentTurnSeat: state.currentTurnSeat,
    hand: cloneValue(getHand(state, seatIndex)),
    legalMoves: getLegalMoves(state, seatIndex),
    prompt: state.pendingEffect?.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE &&
        state.pendingEffect.targetSeat === seatIndex
        ? {
            kind: 'challenge_response',
            sourceSeat: state.pendingEffect.sourceSeat,
            amount: state.pendingEffect.amount
        }
        : null
});

const drawCardsMutable = (state, actorSeat, count, reason, events) => {
    const actorHand = getHand(state, actorSeat).slice();
    const drawnCards = [];
    let reshuffled = false;

    while (drawnCards.length < count) {
        if (!state.drawPile.length) {
            if (state.discardPile.length <= 1) break;
            const topCard = state.discardPile.pop();
            const reshuffledCards = shuffleDeterministic(
                state.discardPile,
                `${state.shuffleSeed}:reshuffle:${state.versionSeed}`
            );
            state.drawPile = reshuffledCards;
            state.discardPile = [topCard];
            reshuffled = true;
            state.versionSeed += 1;
        }

        const nextCard = state.drawPile.shift();
        if (!nextCard) break;
        actorHand.push(nextCard);
        drawnCards.push(nextCard);
    }

    setHand(state, actorSeat, actorHand);
    syncDerivedState(state);

    if (reshuffled) {
        events.push({
            type: 'reshuffle',
            discardCount: state.discardPile.length,
            drawPileCount: state.drawPile.length
        });
    }

    events.push({
        type: 'cards_drawn',
        actorSeat,
        count: drawnCards.length,
        reason
    });

    return drawnCards;
};

const drawCard = ({ state, actorSeat, count = 1, reason = 'draw' }) => {
    const workingState = cloneValue(state);
    const events = [];
    const drawnCards = drawCardsMutable(workingState, actorSeat, count, reason, events);
    assertStateInvariants(workingState);
    return {
        nextState: workingState,
        drawnCards: cloneValue(drawnCards),
        events,
        privateDiffs: {
            [actorSeat]: serializePrivateState({ state: workingState, seatIndex: actorSeat })
        }
    };
};

const finalizeTurnAdvance = (state, actorSeat, events, reason = 'normal') => {
    state.turnContext = {
        phase: 'main',
        drawnCardId: null
    };
    state.currentTurnSeat = nextActiveSeat(state, actorSeat);
    events.push({
        type: 'turn_changed',
        seatIndex: state.currentTurnSeat,
        reason
    });
};

const resolvePendingEffectMutable = (state, events) => {
    const pending = state.pendingEffect;
    if (!pending) {
        return state;
    }

    if (pending.kind === PENDING_EFFECTS.FREEZE) {
        const targetPlayer = getPlayerBySeat(state, pending.targetSeat);
        if (targetPlayer?.statusEffects?.shield) {
            targetPlayer.statusEffects.shield = false;
            state.currentTurnSeat = pending.targetSeat;
            events.push({
                type: 'shield_consumed',
                seatIndex: pending.targetSeat,
                against: PENDING_EFFECTS.FREEZE
            });
        } else {
            state.currentTurnSeat = nextActiveSeat(state, pending.targetSeat);
            events.push({
                type: 'freeze_applied',
                targetSeat: pending.targetSeat,
                skippedToSeat: state.currentTurnSeat
            });
        }
        state.pendingEffect = null;
        state.turnContext = {
            phase: 'main',
            drawnCardId: null
        };
        return state;
    }

    if (pending.kind === PENDING_EFFECTS.PULSE_STACK) {
        const targetPlayer = getPlayerBySeat(state, pending.targetSeat);
        if (targetPlayer?.statusEffects?.shield) {
            targetPlayer.statusEffects.shield = false;
            state.currentTurnSeat = pending.targetSeat;
            state.pendingEffect = null;
            state.turnContext = {
                phase: 'main',
                drawnCardId: null
            };
            events.push({
                type: 'shield_consumed',
                seatIndex: pending.targetSeat,
                against: PENDING_EFFECTS.PULSE_STACK
            });
            return state;
        }

        state.currentTurnSeat = pending.targetSeat;
        state.turnContext = {
            phase: 'main',
            drawnCardId: null
        };
        events.push({
            type: 'pulse_stack_pending',
            targetSeat: pending.targetSeat,
            amount: pending.amount
        });
        return state;
    }

    if (pending.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE) {
        const targetPlayer = getPlayerBySeat(state, pending.targetSeat);
        if (targetPlayer?.statusEffects?.shield) {
            targetPlayer.statusEffects.shield = false;
            state.currentTurnSeat = pending.targetSeat;
            state.pendingEffect = null;
            state.turnContext = {
                phase: 'main',
                drawnCardId: null
            };
            events.push({
                type: 'shield_consumed',
                seatIndex: pending.targetSeat,
                against: PENDING_EFFECTS.PRISM_SURGE_CHALLENGE
            });
            return state;
        }

        state.currentTurnSeat = pending.targetSeat;
        state.turnContext = {
            phase: 'challenge_response',
            drawnCardId: null
        };
        events.push({
            type: 'challenge_window_opened',
            challengerSeat: pending.targetSeat,
            sourceSeat: pending.sourceSeat,
            amount: pending.amount
        });
        return state;
    }

    return state;
};

const resolvePendingEffect = ({ state }) => {
    const workingState = cloneValue(state);
    const events = [];
    resolvePendingEffectMutable(workingState, events);
    syncDerivedState(workingState);
    assertStateInvariants(workingState);
    return {
        nextState: workingState,
        events,
        privateDiffs: {}
    };
};

const refreshLastCardFlags = (state, seatIndex, declareLastCard, events) => {
    const player = getPlayerBySeat(state, seatIndex);
    const handSize = getHand(state, seatIndex).length;
    if (!player) return;

    if (handSize === 1) {
        player.pendingLastCardCall = !declareLastCard;
        player.declaredLastCard = declareLastCard;
        events.push({
            type: declareLastCard ? 'last_card_declared' : 'last_card_alert',
            seatIndex
        });
        return;
    }

    if (handSize !== 1) {
        player.pendingLastCardCall = false;
        player.declaredLastCard = false;
    }
};

const detectRoundEnd = ({ state }) => {
    const activePlayers = state.players.filter((player) => player.status !== 'forfeited');
    if (activePlayers.length === 1) {
        return {
            ended: true,
            winnerSeat: activePlayers[0].seatIndex,
            endReason: 'forfeit'
        };
    }

    const unresolvedChallenge = state.pendingEffect?.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE;
    const emptyHandPlayer = state.players.find((player) => getHand(state, player.seatIndex).length === 0);
    if (emptyHandPlayer && !unresolvedChallenge) {
        return {
            ended: true,
            winnerSeat: emptyHandPlayer.seatIndex,
            endReason: 'hand_empty'
        };
    }

    return {
        ended: false,
        winnerSeat: null,
        endReason: null
    };
};

const cardScore = (card) => {
    if (card.kind === CARD_KINDS.NUMBER) return card.value;
    if (card.kind === CARD_KINDS.PULSE_PLUS_TWO) return 25;
    if (card.kind === CARD_KINDS.PRISM) return 30;
    if (card.kind === CARD_KINDS.PRISM_SURGE) return 40;
    if (card.kind === CARD_KINDS.SWAP) return 25;
    return 20;
};

const calculateRoundResult = ({ state }) => {
    const handPoints = state.players.map((player) => ({
        seatIndex: player.seatIndex,
        userId: player.userId ?? null,
        status: player.status,
        handPoints: getHand(state, player.seatIndex).reduce((total, card) => total + cardScore(card), 0),
        handCount: getHand(state, player.seatIndex).length,
        timeoutStrikes: player.timeoutStrikes
    }));

    const detected = detectRoundEnd({ state });
    const winnerSeat = detected.winnerSeat ?? handPoints.slice().sort((left, right) => {
        if (left.status === 'forfeited' && right.status !== 'forfeited') return 1;
        if (right.status === 'forfeited' && left.status !== 'forfeited') return -1;
        if (left.handPoints !== right.handPoints) return left.handPoints - right.handPoints;
        if (left.handCount !== right.handCount) return left.handCount - right.handCount;
        return left.seatIndex - right.seatIndex;
    })[0]?.seatIndex ?? null;

    const placements = handPoints
        .slice()
        .sort((left, right) => {
            if (left.seatIndex === winnerSeat) return -1;
            if (right.seatIndex === winnerSeat) return 1;
            if (left.status === 'forfeited' && right.status !== 'forfeited') return 1;
            if (right.status === 'forfeited' && left.status !== 'forfeited') return -1;
            if (left.handPoints !== right.handPoints) return left.handPoints - right.handPoints;
            if (left.handCount !== right.handCount) return left.handCount - right.handCount;
            return left.seatIndex - right.seatIndex;
        })
        .map((entry, index) => ({
            placement: index + 1,
            ...entry
        }));

    const winner = placements.find((entry) => entry.seatIndex === winnerSeat) || null;
    const winnerScore = placements
        .filter((entry) => entry.seatIndex !== winnerSeat)
        .reduce((total, entry) => total + entry.handPoints, 0);

    const scoreDeltas = placements.map((entry) => ({
        seatIndex: entry.seatIndex,
        userId: entry.userId,
        scoreDelta: entry.seatIndex === winnerSeat ? winnerScore : -entry.handPoints
    }));

    const rankInputs = placements.map((entry) => ({
        seatIndex: entry.seatIndex,
        userId: entry.userId,
        placement: entry.placement,
        outcome: entry.seatIndex === winnerSeat ? 'win' : (entry.status === 'forfeited' ? 'forfeit' : 'loss'),
        handPointsRemaining: entry.handPoints,
        timeoutStrikes: entry.timeoutStrikes
    }));

    return {
        winnerSeat: winner?.seatIndex ?? null,
        endReason: detected.endReason || 'score_resolve',
        placements,
        scoreDeltas,
        rankInputs
    };
};

const validateMove = ({ state, actorSeat, move }) => {
    const normalizedMove = normalizeMove(move);
    const actor = getPlayerBySeat(state, actorSeat);

    if (state.phase !== 'active') {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.ROUND_NOT_ACTIVE };
    }

    if (!actor || actor.status === 'forfeited') {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.INVALID_TURN };
    }

    if (!normalizedMove.type) {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.MOVE_TYPE_REQUIRED };
    }

    const knownTypes = new Set(Object.values(MOVE_TYPES));
    if (!knownTypes.has(normalizedMove.type)) {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.UNKNOWN_MOVE_TYPE };
    }

    const pendingEffect = state.pendingEffect;
    if (pendingEffect?.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE) {
        if (actorSeat !== pendingEffect.targetSeat) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.INVALID_TURN };
        }
        if (normalizedMove.type === MOVE_TYPES.CHALLENGE || normalizedMove.type === MOVE_TYPES.DECLINE_CHALLENGE) {
            return { ok: true, normalizedMove, errorCode: null };
        }
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.CHALLENGE_RESPONSE_REQUIRED };
    }

    if (actorSeat !== state.currentTurnSeat) {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.INVALID_TURN };
    }

    if (normalizedMove.type === MOVE_TYPES.KEEP_DRAWN) {
        if (state.turnContext.phase !== 'after_draw') {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.KEEP_DRAWN_NOT_AVAILABLE };
        }
        return { ok: true, normalizedMove, errorCode: null };
    }

    if (normalizedMove.type === MOVE_TYPES.DRAW_CARD) {
        if (pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK && pendingEffect.targetSeat === actorSeat) {
            return { ok: true, normalizedMove, errorCode: null };
        }
        if (state.turnContext.phase === 'after_draw') {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.DRAW_ALREADY_PERFORMED };
        }
        return { ok: true, normalizedMove, errorCode: null };
    }

    if (!normalizedMove.cardId) {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.CARD_ID_REQUIRED };
    }

    const hand = getHand(state, actorSeat);
    const card = hand.find((entry) => entry.id === normalizedMove.cardId);
    if (!card) {
        return { ok: false, normalizedMove, errorCode: ERROR_CODES.CARD_NOT_FOUND };
    }

    if (pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK && pendingEffect.targetSeat === actorSeat) {
        if (card.kind !== CARD_KINDS.PULSE_PLUS_TWO) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.STACK_RESPONSE_REQUIRED };
        }
    } else {
        if (state.turnContext.phase === 'after_draw' && state.turnContext.drawnCardId !== card.id) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.ONLY_DRAWN_CARD_PLAYABLE };
        }
        if (!canCardMatchTop(card, state)) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.CARD_NOT_PLAYABLE };
        }
    }

    const requiresHue = card.kind === CARD_KINDS.PRISM ||
        card.kind === CARD_KINDS.PRISM_SURGE ||
        (card.kind === CARD_KINDS.ECHO && [CARD_KINDS.PRISM, CARD_KINDS.PRISM_SURGE].includes(getTopDiscard(state)?.kind));

    if (requiresHue) {
        if (!normalizedMove.chosenHue) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.HUE_REQUIRED };
        }
        if (!validateHue(state.rulesConfig, normalizedMove.chosenHue)) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.INVALID_HUE };
        }
    }

    const requiresTarget = card.kind === CARD_KINDS.SWAP ||
        (card.kind === CARD_KINDS.ECHO && getTopDiscard(state)?.kind === CARD_KINDS.SWAP);

    if (requiresTarget) {
        if (!Number.isInteger(normalizedMove.targetSeat)) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.TARGET_REQUIRED };
        }
        const target = getPlayerBySeat(state, normalizedMove.targetSeat);
        if (!target || target.status === 'forfeited' || target.seatIndex === actorSeat) {
            return { ok: false, normalizedMove, errorCode: ERROR_CODES.INVALID_TARGET };
        }
    }

    return { ok: true, normalizedMove, errorCode: null };
};

const completeRoundIfNeeded = (state, events) => {
    const endCheck = detectRoundEnd({ state });
    if (!endCheck.ended) return;
    state.phase = 'completed';
    state.currentTurnSeat = endCheck.winnerSeat;
    state.roundResult = calculateRoundResult({ state });
    events.push({
        type: 'round_finished',
        winnerSeat: state.roundResult.winnerSeat,
        endReason: state.roundResult.endReason
    });
};

const applyEchoEffect = (state, actorSeat, normalizedMove, previousTop, events) => {
    if (!previousTop || previousTop.kind === CARD_KINDS.NUMBER) {
        state.currentHue = getTopDiscard(state)?.hue ?? state.currentHue;
        finalizeTurnAdvance(state, actorSeat, events, 'echo_noop');
        return;
    }

    if (previousTop.kind === CARD_KINDS.FREEZE) {
        state.pendingEffect = {
            kind: PENDING_EFFECTS.FREEZE,
            sourceSeat: actorSeat,
            targetSeat: nextActiveSeat(state, actorSeat),
            echoedFrom: previousTop.kind
        };
        state.currentHue = getTopDiscard(state)?.hue ?? state.currentHue;
        resolvePendingEffectMutable(state, events);
        return;
    }

    if (previousTop.kind === CARD_KINDS.FLIP_FLOW) {
        state.direction *= -1;
        if (activeSeatOrder(state).length === 2) {
            state.currentTurnSeat = actorSeat;
        } else {
            state.currentTurnSeat = nextActiveSeat(state, actorSeat, 1, state.direction);
        }
        state.turnContext = { phase: 'main', drawnCardId: null };
        state.currentHue = getTopDiscard(state)?.hue ?? state.currentHue;
        events.push({
            type: 'direction_changed',
            direction: state.direction,
            reason: 'echo'
        });
        events.push({
            type: 'turn_changed',
            seatIndex: state.currentTurnSeat,
            reason: 'flip_flow'
        });
        return;
    }

    if (previousTop.kind === CARD_KINDS.PULSE_PLUS_TWO) {
        const existingAmount = state.pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK
            ? state.pendingEffect.amount
            : 0;
        state.pendingEffect = {
            kind: PENDING_EFFECTS.PULSE_STACK,
            sourceSeat: actorSeat,
            targetSeat: nextActiveSeat(state, actorSeat),
            amount: existingAmount + 2,
            echoedFrom: previousTop.kind
        };
        state.currentHue = getTopDiscard(state)?.hue ?? state.currentHue;
        resolvePendingEffectMutable(state, events);
        return;
    }

    if (previousTop.kind === CARD_KINDS.PRISM) {
        state.currentHue = normalizedMove.chosenHue;
        finalizeTurnAdvance(state, actorSeat, events, 'echo_prism');
        return;
    }

    if (previousTop.kind === CARD_KINDS.PRISM_SURGE) {
        const originalTopCard = state.discardPile[state.discardPile.length - 2];
        state.currentHue = normalizedMove.chosenHue;
        state.pendingEffect = {
            kind: PENDING_EFFECTS.PRISM_SURGE_CHALLENGE,
            sourceSeat: actorSeat,
            targetSeat: nextActiveSeat(state, actorSeat),
            amount: 4,
            chosenHue: normalizedMove.chosenHue,
            originalTopCard: originalTopCard ? stableCardView(originalTopCard) : null,
            offenderHadPlayableAlternative: false,
            echoedFrom: previousTop.kind
        };
        resolvePendingEffectMutable(state, events);
        return;
    }

    if (previousTop.kind === CARD_KINDS.SHIELD) {
        const actor = getPlayerBySeat(state, actorSeat);
        actor.statusEffects.shield = true;
        state.currentHue = getTopDiscard(state)?.hue ?? state.currentHue;
        events.push({
            type: 'shield_granted',
            seatIndex: actorSeat,
            reason: 'echo'
        });
        finalizeTurnAdvance(state, actorSeat, events, 'shield');
        return;
    }

    if (previousTop.kind === CARD_KINDS.SWAP) {
        const actorHand = getHand(state, actorSeat).slice();
        const targetHand = getHand(state, normalizedMove.targetSeat).slice();
        setHand(state, actorSeat, targetHand);
        setHand(state, normalizedMove.targetSeat, actorHand);
        state.currentHue = getTopDiscard(state)?.hue ?? state.currentHue;
        events.push({
            type: 'hands_swapped',
            sourceSeat: actorSeat,
            targetSeat: normalizedMove.targetSeat,
            reason: 'echo'
        });
        finalizeTurnAdvance(state, actorSeat, events, 'swap');
        return;
    }

    finalizeTurnAdvance(state, actorSeat, events, 'echo');
};

const resolveChallenge = ({ state, challengerSeat, decision }) => {
    const workingState = cloneValue(state);
    const events = [];
    const pending = workingState.pendingEffect;

    if (!pending || pending.kind !== PENDING_EFFECTS.PRISM_SURGE_CHALLENGE || pending.targetSeat !== challengerSeat) {
        throw new Error(ERROR_CODES.CHALLENGE_NOT_AVAILABLE);
    }

    const normalizedDecision = String(decision || '').trim().toLowerCase();
    if (normalizedDecision !== 'challenge' && normalizedDecision !== 'decline') {
        throw new Error(ERROR_CODES.CHALLENGE_NOT_AVAILABLE);
    }

    if (normalizedDecision === 'decline') {
        const declinedDraw = drawCardsMutable(workingState, challengerSeat, pending.amount, 'prism_surge_decline', events);
        workingState.pendingEffect = null;
        workingState.turnContext = {
            phase: 'main',
            drawnCardId: null
        };
        workingState.currentTurnSeat = nextActiveSeat(workingState, challengerSeat);
        events.push({
            type: 'challenge_declined',
            challengerSeat,
            cardsDrawn: declinedDraw.length,
            nextSeat: workingState.currentTurnSeat
        });
    } else if (pending.offenderHadPlayableAlternative) {
        const offenderDraw = drawCardsMutable(workingState, pending.sourceSeat, pending.amount, 'prism_surge_failed_inspect', events);
        workingState.pendingEffect = null;
        workingState.turnContext = {
            phase: 'main',
            drawnCardId: null
        };
        workingState.currentTurnSeat = challengerSeat;
        events.push({
            type: 'challenge_resolved',
            outcome: 'successful',
            challengerSeat,
            offenderSeat: pending.sourceSeat,
            cardsDrawn: offenderDraw.length
        });
    } else {
        const failedDraw = drawCardsMutable(
            workingState,
            challengerSeat,
            pending.amount + workingState.rulesConfig.challengePenaltyBonus,
            'failed_challenge_penalty',
            events
        );
        workingState.pendingEffect = null;
        workingState.turnContext = {
            phase: 'main',
            drawnCardId: null
        };
        workingState.currentTurnSeat = nextActiveSeat(workingState, challengerSeat);
        events.push({
            type: 'challenge_resolved',
            outcome: 'failed',
            challengerSeat,
            offenderSeat: pending.sourceSeat,
            cardsDrawn: failedDraw.length,
            nextSeat: workingState.currentTurnSeat
        });
    }

    syncDerivedState(workingState);
    completeRoundIfNeeded(workingState, events);
    assertStateInvariants(workingState);
    return {
        nextState: workingState,
        outcome: events[events.length - 1] || null,
        events,
        privateDiffs: {
            [challengerSeat]: serializePrivateState({ state: workingState, seatIndex: challengerSeat }),
            [pending.sourceSeat]: serializePrivateState({ state: workingState, seatIndex: pending.sourceSeat })
        }
    };
};

const applyMove = ({ state, actorSeat, move }) => {
    const validation = validateMove({ state, actorSeat, move });
    if (!validation.ok) {
        throw new Error(validation.errorCode);
    }

    const normalizedMove = validation.normalizedMove;
    if (normalizedMove.type === MOVE_TYPES.CHALLENGE) {
        return resolveChallenge({ state, challengerSeat: actorSeat, decision: 'challenge' });
    }
    if (normalizedMove.type === MOVE_TYPES.DECLINE_CHALLENGE) {
        return resolveChallenge({ state, challengerSeat: actorSeat, decision: 'decline' });
    }

    const workingState = cloneValue(state);
    const events = [];
    const privateDiffs = {};

    const hand = getHand(workingState, actorSeat).slice();

    if (normalizedMove.type === MOVE_TYPES.DRAW_CARD) {
        if (workingState.pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK &&
            workingState.pendingEffect.targetSeat === actorSeat) {
            const drawAmount = workingState.pendingEffect.amount;
            drawCardsMutable(workingState, actorSeat, drawAmount, 'pulse_stack_penalty', events);
            workingState.pendingEffect = null;
            finalizeTurnAdvance(workingState, actorSeat, events, 'pulse_stack_resolved');
            syncDerivedState(workingState);
            completeRoundIfNeeded(workingState, events);
            assertStateInvariants(workingState);
            privateDiffs[actorSeat] = serializePrivateState({ state: workingState, seatIndex: actorSeat });
            return {
                nextState: workingState,
                events,
                privateDiffs
            };
        }

        const drawnCards = drawCardsMutable(workingState, actorSeat, 1, 'turn_draw', events);
        const drawnCard = drawnCards[0] || null;
        if (drawnCard && canCardMatchTop(drawnCard, workingState)) {
            workingState.turnContext = {
                phase: 'after_draw',
                drawnCardId: drawnCard.id
            };
            events.push({
                type: 'draw_option_opened',
                actorSeat
            });
        } else {
            finalizeTurnAdvance(workingState, actorSeat, events, 'draw_pass');
        }

        syncDerivedState(workingState);
        assertStateInvariants(workingState);
        privateDiffs[actorSeat] = serializePrivateState({ state: workingState, seatIndex: actorSeat });
        return {
            nextState: workingState,
            events,
            privateDiffs
        };
    }

    if (normalizedMove.type === MOVE_TYPES.KEEP_DRAWN) {
        finalizeTurnAdvance(workingState, actorSeat, events, 'keep_drawn');
        syncDerivedState(workingState);
        assertStateInvariants(workingState);
        privateDiffs[actorSeat] = serializePrivateState({ state: workingState, seatIndex: actorSeat });
        return {
            nextState: workingState,
            events,
            privateDiffs
        };
    }

    const cardIndex = hand.findIndex((card) => card.id === normalizedMove.cardId);
    const [playedCard] = hand.splice(cardIndex, 1);
    const stateBeforePlay = cloneValue(workingState);
    setHand(workingState, actorSeat, hand);
    workingState.discardPile.push(playedCard);
    workingState.turnContext = {
        phase: 'main',
        drawnCardId: null
    };

    events.push({
        type: 'card_played',
        actorSeat,
        card: stableCardView(playedCard),
        chosenHue: normalizedMove.chosenHue ?? null
    });

    if (playedCard.kind === CARD_KINDS.NUMBER) {
        workingState.currentHue = playedCard.hue;
        finalizeTurnAdvance(workingState, actorSeat, events, 'number');
    } else if (playedCard.kind === CARD_KINDS.FREEZE) {
        workingState.currentHue = playedCard.hue;
        workingState.pendingEffect = {
            kind: PENDING_EFFECTS.FREEZE,
            sourceSeat: actorSeat,
            targetSeat: nextActiveSeat(workingState, actorSeat)
        };
        resolvePendingEffectMutable(workingState, events);
    } else if (playedCard.kind === CARD_KINDS.FLIP_FLOW) {
        workingState.currentHue = playedCard.hue;
        workingState.direction *= -1;
        if (activeSeatOrder(workingState).length === 2) {
            workingState.currentTurnSeat = actorSeat;
        } else {
            workingState.currentTurnSeat = nextActiveSeat(workingState, actorSeat, 1, workingState.direction);
        }
        events.push({
            type: 'direction_changed',
            direction: workingState.direction,
            reason: CARD_KINDS.FLIP_FLOW
        });
        events.push({
            type: 'turn_changed',
            seatIndex: workingState.currentTurnSeat,
            reason: CARD_KINDS.FLIP_FLOW
        });
    } else if (playedCard.kind === CARD_KINDS.PULSE_PLUS_TWO) {
        workingState.currentHue = playedCard.hue;
        const existingAmount = state.pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK
            ? state.pendingEffect.amount
            : 0;
        workingState.pendingEffect = {
            kind: PENDING_EFFECTS.PULSE_STACK,
            sourceSeat: actorSeat,
            targetSeat: nextActiveSeat(workingState, actorSeat),
            amount: existingAmount + 2
        };
        resolvePendingEffectMutable(workingState, events);
    } else if (playedCard.kind === CARD_KINDS.PRISM) {
        workingState.currentHue = normalizedMove.chosenHue;
        finalizeTurnAdvance(workingState, actorSeat, events, CARD_KINDS.PRISM);
    } else if (playedCard.kind === CARD_KINDS.PRISM_SURGE) {
        workingState.currentHue = normalizedMove.chosenHue;
        workingState.pendingEffect = {
            kind: PENDING_EFFECTS.PRISM_SURGE_CHALLENGE,
            sourceSeat: actorSeat,
            targetSeat: nextActiveSeat(workingState, actorSeat),
            amount: 4,
            chosenHue: normalizedMove.chosenHue,
            originalTopCard: stableCardView(getTopDiscard(stateBeforePlay)),
            offenderHadPlayableAlternative: hasAlternativePlayableCard(stateBeforePlay, actorSeat, playedCard.id)
        };
        resolvePendingEffectMutable(workingState, events);
    } else if (playedCard.kind === CARD_KINDS.SHIELD) {
        const actor = getPlayerBySeat(workingState, actorSeat);
        actor.statusEffects.shield = true;
        workingState.currentHue = playedCard.hue;
        events.push({
            type: 'shield_granted',
            seatIndex: actorSeat
        });
        finalizeTurnAdvance(workingState, actorSeat, events, CARD_KINDS.SHIELD);
    } else if (playedCard.kind === CARD_KINDS.ECHO) {
        workingState.currentHue = playedCard.hue;
        const previousTop = stateBeforePlay.discardPile[stateBeforePlay.discardPile.length - 1] || null;
        applyEchoEffect(workingState, actorSeat, normalizedMove, previousTop, events);
    } else if (playedCard.kind === CARD_KINDS.SWAP) {
        const actorHand = getHand(workingState, actorSeat).slice();
        const targetHand = getHand(workingState, normalizedMove.targetSeat).slice();
        setHand(workingState, actorSeat, targetHand);
        setHand(workingState, normalizedMove.targetSeat, actorHand);
        workingState.currentHue = playedCard.hue;
        events.push({
            type: 'hands_swapped',
            sourceSeat: actorSeat,
            targetSeat: normalizedMove.targetSeat
        });
        finalizeTurnAdvance(workingState, actorSeat, events, CARD_KINDS.SWAP);
    }

    refreshLastCardFlags(workingState, actorSeat, normalizedMove.declareLastCard, events);
    syncDerivedState(workingState);
    completeRoundIfNeeded(workingState, events);
    assertStateInvariants(workingState);

    privateDiffs[actorSeat] = serializePrivateState({ state: workingState, seatIndex: actorSeat });
    if (Number.isInteger(normalizedMove.targetSeat)) {
        privateDiffs[normalizedMove.targetSeat] = serializePrivateState({ state: workingState, seatIndex: normalizedMove.targetSeat });
    }
    if (workingState.pendingEffect?.targetSeat !== undefined) {
        privateDiffs[workingState.pendingEffect.targetSeat] = serializePrivateState({
            state: workingState,
            seatIndex: workingState.pendingEffect.targetSeat
        });
    }

    return {
        nextState: workingState,
        events,
        privateDiffs
    };
};

const autoActionOnTimeout = ({ state }) => {
    const workingState = cloneValue(state);
    const actor = getPlayerBySeat(workingState, workingState.currentTurnSeat);
    const events = [];
    if (!actor) {
        throw new Error(ERROR_CODES.INVALID_TURN);
    }

    actor.timeoutStrikes += 1;
    events.push({
        type: 'timeout_recorded',
        seatIndex: actor.seatIndex,
        totalStrikes: actor.timeoutStrikes
    });

    if (actor.timeoutStrikes >= workingState.rulesConfig.timeoutStrikeLimit) {
        actor.status = 'forfeited';
        syncDerivedState(workingState);
        completeRoundIfNeeded(workingState, events);
        assertStateInvariants(workingState);
        return {
            nextState: workingState,
            autoMove: {
                type: 'forfeit'
            },
            events,
            privateDiffs: {}
        };
    }

    if (workingState.pendingEffect?.kind === PENDING_EFFECTS.PRISM_SURGE_CHALLENGE) {
        const resolved = resolveChallenge({
            state: workingState,
            challengerSeat: actor.seatIndex,
            decision: 'decline'
        });
        return {
            nextState: resolved.nextState,
            autoMove: {
                type: MOVE_TYPES.DECLINE_CHALLENGE
            },
            events: events.concat(resolved.events),
            privateDiffs: resolved.privateDiffs
        };
    }

    if (workingState.pendingEffect?.kind === PENDING_EFFECTS.PULSE_STACK &&
        workingState.pendingEffect.targetSeat === actor.seatIndex) {
        const resolved = applyMove({
            state: workingState,
            actorSeat: actor.seatIndex,
            move: {
                type: MOVE_TYPES.DRAW_CARD
            }
        });
        return {
            nextState: resolved.nextState,
            autoMove: {
                type: MOVE_TYPES.DRAW_CARD
            },
            events: events.concat(resolved.events),
            privateDiffs: resolved.privateDiffs
        };
    }

    if (workingState.turnContext.phase === 'after_draw') {
        const resolved = applyMove({
            state: workingState,
            actorSeat: actor.seatIndex,
            move: {
                type: MOVE_TYPES.KEEP_DRAWN
            }
        });
        return {
            nextState: resolved.nextState,
            autoMove: {
                type: MOVE_TYPES.KEEP_DRAWN
            },
            events: events.concat(resolved.events),
            privateDiffs: resolved.privateDiffs
        };
    }

    const drawResult = drawCard({
        state: workingState,
        actorSeat: actor.seatIndex,
        count: 1,
        reason: 'timeout_draw'
    });

    const afterDrawState = drawResult.nextState;
    afterDrawState.turnContext = {
        phase: 'main',
        drawnCardId: null
    };
    finalizeTurnAdvance(afterDrawState, actor.seatIndex, drawResult.events, 'timeout_pass');
    syncDerivedState(afterDrawState);
    assertStateInvariants(afterDrawState);

    return {
        nextState: afterDrawState,
        autoMove: {
            type: 'timeout_draw_pass'
        },
        events: events.concat(drawResult.events),
        privateDiffs: {
            [actor.seatIndex]: serializePrivateState({ state: afterDrawState, seatIndex: actor.seatIndex })
        }
    };
};

const createInitialState = ({ players, rulesConfig, shuffleSeed, roundNumber = 1 }) => {
    if (!Array.isArray(players) || players.length < 2) {
        throw new Error(ERROR_CODES.INVALID_PLAYERS);
    }

    const sortedPlayers = sortPlayers(players);
    const seatSet = new Set();
    for (const player of sortedPlayers) {
        if (!Number.isInteger(player.seatIndex)) {
            throw new Error(ERROR_CODES.INVALID_PLAYERS);
        }
        if (seatSet.has(player.seatIndex)) {
            throw new Error(ERROR_CODES.DUPLICATE_SEAT);
        }
        seatSet.add(player.seatIndex);
    }

    const normalizedRules = normalizeRulesConfig(rulesConfig);
    const baseDeck = buildDeck(normalizedRules);
    const shuffledDeck = shuffleDeterministic(baseDeck, shuffleSeed);
    const handsBySeat = {};
    for (const player of sortedPlayers) {
        handsBySeat[String(player.seatIndex)] = [];
    }

    const drawPile = shuffledDeck.slice();
    for (let drawIndex = 0; drawIndex < normalizedRules.startingHandSize; drawIndex += 1) {
        for (const player of sortedPlayers) {
            const nextCard = drawPile.shift();
            if (!nextCard) throw new Error(ERROR_CODES.INTERNAL_INVALID_STATE);
            handsBySeat[String(player.seatIndex)].push(nextCard);
        }
    }

    let initialDiscard = drawPile.shift();
    while (initialDiscard && initialDiscard.kind !== CARD_KINDS.NUMBER) {
        drawPile.push(initialDiscard);
        initialDiscard = drawPile.shift();
    }

    if (!initialDiscard) {
        throw new Error(ERROR_CODES.INTERNAL_INVALID_STATE);
    }

    const state = {
        gameId: GAME_ID,
        phase: 'active',
        roundNumber,
        shuffleSeed: String(shuffleSeed ?? '0'),
        versionSeed: 1,
        rulesConfig: normalizedRules,
        deckDefinition: {
            totalCards: baseDeck.length,
            allCardIds: baseDeck.map((card) => card.id)
        },
        players: sortedPlayers.map((player) => ({
            seatIndex: player.seatIndex,
            userId: player.userId ?? null,
            status: 'active',
            handCount: 0,
            timeoutStrikes: 0,
            pendingLastCardCall: false,
            declaredLastCard: false,
            statusEffects: {
                shield: false
            }
        })),
        handsBySeat,
        drawPile,
        discardPile: [initialDiscard],
        discardTop: initialDiscard,
        currentTurnSeat: sortedPlayers[0].seatIndex,
        direction: 1,
        currentHue: initialDiscard.hue,
        pendingEffect: null,
        turnContext: {
            phase: 'main',
            drawnCardId: null
        },
        roundResult: null
    };

    syncDerivedState(state);
    assertStateInvariants(state);

    return {
        state,
        events: [
            {
                type: 'round_started',
                roundNumber
            },
            {
                type: 'initial_discard',
                card: stableCardView(initialDiscard),
                currentHue: initialDiscard.hue
            },
            {
                type: 'turn_changed',
                seatIndex: state.currentTurnSeat,
                reason: 'initial_turn'
            }
        ]
    };
};

module.exports = {
    GAME_ID,
    CARD_KINDS,
    MOVE_TYPES,
    ERROR_CODES,
    createInitialState,
    validateMove,
    applyMove,
    drawCard,
    resolvePendingEffect,
    resolveChallenge,
    autoActionOnTimeout,
    detectRoundEnd,
    calculateRoundResult,
    serializePublicState,
    serializePrivateState
};
