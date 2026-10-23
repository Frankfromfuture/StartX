const { syncContent } = require('../../tools/sync-content.cjs');
exports.throwError = true;
exports.onBeforeBuild = async function () {
    const synced = await syncContent();
    if (synced.changed.length) {
        await Editor.Message.request('asset-db', 'refresh-asset', 'db://assets/content');
        await Editor.Message.request('asset-db', 'refresh-asset', 'db://assets/sample');
    }
};
