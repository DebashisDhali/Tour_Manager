const express = require('express');
const router = express.Router();
const tourController = require('../controllers/tourController');

router.post('/', tourController.createTour);
router.get('/', tourController.getAllTours);
router.post('/join', tourController.joinTour);

router.get('/:id', tourController.getTourDetails);


module.exports = router;
