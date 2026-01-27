const express = require('express');
const router = express.Router();
const settlementController = require('../controllers/settlementController');

router.post('/', settlementController.createSettlement);
router.get('/tour/:tourId', settlementController.getSettlementsByTour);
router.delete('/:id', settlementController.deleteSettlement);

module.exports = router;
