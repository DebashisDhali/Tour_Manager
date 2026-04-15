const express = require('express');
const router = express.Router();
const aiController = require('../controllers/aiController');
const rbac = require('../middleware/rbac');

router.post('/:tourId/insights', aiController.getTourInsights);

module.exports = router;
