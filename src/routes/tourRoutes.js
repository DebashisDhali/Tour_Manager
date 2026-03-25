const express = require('express');
const router = express.Router();
const tourController = require('../controllers/tourController');
const auth = require('../middleware/auth');

router.post('/', auth, tourController.createTour);
router.get('/', auth, tourController.getAllTours);
router.post('/join', auth, tourController.joinTour);

router.get('/:id', auth, tourController.getTourDetails);
router.post('/:tourId/add-member', auth, tourController.addMember);
router.post('/delete', auth, tourController.deleteTour);
router.post('/remove-member', auth, tourController.removeMember);
router.patch('/:tourId/members/:userId/role', auth, tourController.updateMemberRole);

module.exports = router;
