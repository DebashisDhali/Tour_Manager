const express = require('express');
const router = express.Router();
const expenseController = require('../controllers/expenseController');

const rbac = require('../middleware/rbac');

router.post('/', rbac.checkTourAccess(['admin', 'editor']), expenseController.createExpense);
router.get('/tour/:tourId', rbac.checkTourAccess(['admin', 'editor', 'viewer']), expenseController.getExpensesByTour);
router.put('/:id', rbac.checkTourAccess(['admin', 'editor']), expenseController.updateExpense);
router.delete('/:id', rbac.checkTourAccess(['admin', 'editor']), expenseController.deleteExpense);
router.post('/sync', expenseController.syncExpenses); // Sync handles its own batch checks or you can add a general member check

module.exports = router;
