const express = require('express');
const router = express.Router();
const tourController = require('../controllers/tourController');
const auth = require('../middleware/auth');
const rbac = require('../middleware/rbac');
const joinRequestController = require('../controllers/joinRequestController');

router.post('/', auth, tourController.createTour);
router.get('/', auth, tourController.getAllTours);
router.post('/join', auth, tourController.joinTour);
router.post('/:tourId/invite-code/regenerate', auth, rbac.checkTourAccess(['admin']), tourController.regenerateInviteCode);

// Temporary Diagnostic Route (no auth for direct inspection via ping)
router.get('/diagnostic/db-schema', tourController.checkDbSchema);

// Join Requests
router.get('/find/:code', auth, tourController.findTourByCode);
router.post('/:tourId/request-join', auth, joinRequestController.createJoinRequest);
router.get('/:tourId/requests', auth, rbac.checkTourAccess(['admin']), joinRequestController.getTourRequests);
router.patch('/requests/:requestId', auth, rbac.checkTourAccess(['admin']), joinRequestController.handleJoinRequest);

router.get('/:id', auth, rbac.checkTourAccess(['admin', 'editor', 'viewer']), tourController.getTourDetails);
router.post('/:tourId/add-member', auth, rbac.checkTourAccess(['admin']), tourController.addMember);
router.post('/delete', auth, rbac.checkTourAccess(['admin']), tourController.deleteTour);
router.post('/remove-member', auth, rbac.checkTourAccess(['admin']), tourController.removeMember);
router.patch('/:tourId/members/:userId/role', auth, rbac.checkTourAccess(['admin']), tourController.updateMemberRole);
router.post('/:tourId/members/:userId/retroactive-split', auth, rbac.checkTourAccess(['admin']), tourController.retroactiveSplit);

module.exports = router;
