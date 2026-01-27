const express = require('express');
const router = express.Router();
const expenseController = require('../controllers/expenseController');

router.post('/', expenseController.createExpense);
router.get('/tour/:tourId', expenseController.getExpensesByTour);
router.put('/:id', expenseController.updateExpense);
router.delete('/:id', expenseController.deleteExpense);
router.post('/sync', expenseController.syncExpenses);

module.exports = router;
