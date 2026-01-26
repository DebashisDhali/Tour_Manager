const express = require('express');
const router = express.Router();
const expenseController = require('../controllers/expenseController');

router.post('/', expenseController.createExpense);
router.get('/tour/:tourId', expenseController.getExpensesByTour);
router.post('/sync', expenseController.syncExpenses);

module.exports = router;
