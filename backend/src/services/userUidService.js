const User = require('../models/User');

let backfillPromise = null;

const backfillMissingUserUids = async () => {
    if (backfillPromise) {
        return backfillPromise;
    }

    backfillPromise = User.backfillMissingUids()
        .then((updatedCount) => {
            if (updatedCount > 0) {
                console.log(`Assigned permanent UIDs to ${updatedCount} existing users`);
            }
            return updatedCount;
        })
        .catch((error) => {
            console.error('User UID backfill failed:', error.message);
            throw error;
        })
        .finally(() => {
            backfillPromise = null;
        });

    return backfillPromise;
};

module.exports = {
    backfillMissingUserUids
};
