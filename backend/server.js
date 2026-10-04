const express = require('express');
const cors = require('cors');
require('dotenv').config();

const { tenantContextMiddleware } = require('./middleware/tenantContext');
const usersRouter = require('./routes/users');
const licensesRouter = require('./routes/licenses');
const seatAllocationsRouter = require('./routes/seatAllocations');

const app = express();
const PORT = process.env.PORT || 5000;

// Enable Cross-Origin Resource Sharing
app.use(cors());

// Parse incoming JSON request payloads
app.use(express.json());

// Attach AsyncLocalStorage tenant context middleware globally
app.use(tenantContextMiddleware);

// Health Check Endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'UP',
        service: 'Multi-Tenant Digital Asset & License Management API',
        timestamp: new Date().toISOString()
    });
});

// Mount Resource Routers
app.use('/users', usersRouter);
app.use('/licenses', licensesRouter);
app.use('/seat-allocations', seatAllocationsRouter);

// Alias mounting under /api prefix
app.use('/api/users', usersRouter);
app.use('/api/licenses', licensesRouter);
app.use('/api/seat-allocations', seatAllocationsRouter);

// 404 Route Handler
app.use((req, res) => {
    res.status(404).json({
        error: 'Not Found',
        message: `Cannot ${req.method} ${req.originalUrl}`
    });
});

// Global Error Handler Middleware
app.use((err, req, res, next) => {
    console.error('Unhandled Application Error:', err);
    res.status(err.status || 500).json({
        error: 'Internal Server Error',
        message: err.message || 'An unexpected database or server error occurred.'
    });
});

// Start Express Server
if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`=====================================================================`);
        console.log(`🚀 Multi-Tenant SaaS Backend Server running on port ${PORT}`);
        console.log(`🔒 AsyncLocalStorage tenant context middleware ACTIVE`);
        console.log(`=====================================================================`);
    });
}

module.exports = app;
