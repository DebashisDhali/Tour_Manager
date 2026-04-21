const express = require('express');
const router = express.Router();
const aiController = require('../controllers/aiController');
const rbac = require('../middleware/rbac');

const auth = require('../middleware/auth');

router.post('/:tourId/insights', auth, rbac.checkTourAccess(['admin', 'editor', 'viewer']), aiController.getTourInsights);

module.exports = router;
