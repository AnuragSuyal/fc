const mongoose = require('mongoose');
const User = require('./src/models/User');
const Gift = require('./src/models/Gift');
const Transaction = require('./src/models/Transaction');
const Room = require('./src/models/Room');
const Post = require('./src/models/Post');
const Message = require('./src/models/Message');
const Group = require('./src/models/Group');

function inspectSchema(name, schema) {
    if (!schema || !schema.s || !schema.s.hooks) {
        console.log(`\n--- ${name} (No hooks found) ---`);
        return;
    }
    console.log(`\n--- ${name} ---`);
    ['save', 'validate', 'remove'].forEach(hookType => {
        const hooks = schema.s.hooks.pre.get(hookType) || [];
        console.log(`${hookType} PRE hooks: ${hooks.length}`);
        hooks.forEach((h, i) => {
            console.log(`  [${i}] ${h.fn.toString().substring(0, 100).replace(/\n/g, ' ')}...`);
            console.log(`      isAsync: ${h.fn.constructor.name === 'AsyncFunction'}`);
            console.log(`      args: ${h.fn.length}`);
        });

        const postHooks = schema.s.hooks.post.get(hookType) || [];
        console.log(`${hookType} POST hooks: ${postHooks.length}`);
        postHooks.forEach((h, i) => {
            console.log(`  [${i}] ${h.fn.toString().substring(0, 100).replace(/\n/g, ' ')}...`);
            console.log(`      isAsync: ${h.fn.constructor.name === 'AsyncFunction'}`);
            console.log(`      args: ${h.fn.length}`);
        });
    });
}

inspectSchema('User', User.schema);
inspectSchema('Gift', Gift.schema);
inspectSchema('Transaction', Transaction.schema);
inspectSchema('Room', Room.schema);
inspectSchema('Post', Post.schema);
inspectSchema('Message', Message.schema);
inspectSchema('Group', Group.schema);
process.exit(0);






