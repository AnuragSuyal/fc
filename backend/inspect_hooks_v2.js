const mongoose = require('mongoose');
const User = require('./src/models/User');
const Gift = require('./src/models/Gift');
const Transaction = require('./src/models/Transaction');
const Room = require('./src/models/Room');
const Post = require('./src/models/Post');
const Message = require('./src/models/Message');
const Group = require('./src/models/Group');

const models = { User, Gift, Transaction, Room, Post, Message, Group };

for (const [name, model] of Object.entries(models)) {
    console.log(`\n--- ${name} ---`);
    const schema = model.schema;
    if (!schema || !schema.s || !schema.s.hooks) {
        console.log('No hooks found');
        continue;
    }

    ['pre', 'post'].forEach(type => {
        const hooks = schema.s.hooks[type];
        if (!hooks) return;

        for (const [op, list] of hooks) {
            console.log(`${type} ${op} hooks: ${list.length}`);
            list.forEach((h, i) => {
                const fnStr = h.fn.toString().replace(/\s+/g, ' ');
                console.log(`  [${i}] ${fnStr.substring(0, 100)}...`);
                console.log(`      args: ${h.fn.length}`);
            });
        }
    });
}
process.exit(0);






