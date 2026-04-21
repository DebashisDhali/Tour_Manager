const express = require('express');
const router = express.Router();
const controller = require('../controllers/programIncomeController');
const rbac = require('../middleware/rbac');

// Assuming you have tourId in req.body for create/delete, or need to verify inside controller.
// rbac checks req.params.tourId or req.body.tourId
router.post('/', rbac.checkTourAccess(['admin', 'editor']), controller.createProgramIncome);
router.post('/delete', rbac.checkTourAccess(['admin', 'editor']), controller.deleteProgramIncome); 
router.get('/:tourId', rbac.checkTourAccess(['admin', 'editor', 'viewer']), controller.getIncomesByTour);

module.exports = router;
