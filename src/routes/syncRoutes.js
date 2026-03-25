const express = require('express');
const router = express.Router();
const syncController = require('../controllers/syncController');
const auth = require('../middleware/auth');

router.post('/', auth, syncController.syncData);

module.exports = router;
