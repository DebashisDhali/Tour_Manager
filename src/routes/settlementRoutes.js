const express = require('express');
const router = express.Router();
const settlementController = require('../controllers/settlementController');
const rbac = require('../middleware/rbac');
const auth = require('../middleware/auth');

router.post('/', auth, rbac.checkTourAccess(['admin', 'editor']), settlementController.createSettlement);
router.get('/tour/:tourId', auth, rbac.checkTourAccess(['admin', 'editor', 'viewer']), settlementController.getSettlementsByTour);
router.delete('/:id', auth, rbac.checkTourAccess(['admin', 'editor']), settlementController.deleteSettlement);

module.exports = router;
