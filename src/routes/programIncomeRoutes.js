const express = require('express');
const router = express.Router();
const controller = require('../controllers/programIncomeController');

router.post('/', controller.createProgramIncome);
router.post('/delete', controller.deleteProgramIncome); // Delete by ID in body
router.get('/:tourId', controller.getIncomesByTour);

module.exports = router;
