const { AsyncLocalStorage } = require('async_hooks');

// Instantiate AsyncLocalStorage to store per-request tenant context
const tenantStorage = new AsyncLocalStorage();

/**
 * Express middleware to capture tenant ID from incoming HTTP headers
 * and propagate it safely across asynchronous execution context.
 */
function tenantContextMiddleware(req, res, next) {
    const tenantId = 
        req.headers['x-tenant-id'] || 
        req.headers['tenant-id'] || 
        req.query.tenant_id || 
        null;

    tenantStorage.run({ tenantId }, () => {
        next();
    });
}

/**
 * Helper to retrieve current tenant ID from AsyncLocalStorage store
 */
function getTenantId() {
    const store = tenantStorage.getStore();
    return store ? store.tenantId : null;
}

module.exports = {
    tenantStorage,
    tenantContextMiddleware,
    getTenantId
};
