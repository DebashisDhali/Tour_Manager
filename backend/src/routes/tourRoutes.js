const express = require('express');
const router = express.Router();
const tourController = require('../controllers/tourController');

router.post('/', tourController.createTour);
router.get('/', tourController.getAllTours);
router.post('/join', tourController.joinTour);
router.get('/:tourId/requests', tourController.getPendingRequests);
router.post('/requests/:requestId/approve', tourController.approveJoinRequest);
router.get('/:id', tourController.getTourDetails);


module.exports = router;
