const express = require('express');
const router = express.Router();
const tourController = require('../controllers/tourController');
const auth = require('../middleware/auth');
const rbac = require('../middleware/rbac');
const joinRequestController = require('../controllers/joinRequestController');

router.post('/', auth, tourController.createTour);
router.get('/', auth, tourController.getAllTours);
router.post('/join', auth, tourController.joinTour);
router.get('/invitations/my', auth, tourController.getMyInvitations);
router.patch('/:tourId/invitations/respond', auth, tourController.respondToInvitation);
router.post('/:tourId/invite-code/regenerate', auth, rbac.checkTourAccess(['admin', 'editor']), tourController.regenerateInviteCode);

// Diagnostic route only for non-production authenticated checks.
router.get('/diagnostic/db-schema', auth, (req, res, next) => {
	if (process.env.NODE_ENV === 'production') {
		return res.status(404).json({ error: 'Not found' });
	}
	return next();
}, tourController.checkDbSchema);

// Join Requests
router.get('/find/:code', auth, tourController.findTourByCode);
router.post('/:tourId/request-join', auth, joinRequestController.createJoinRequest);
router.get('/:tourId/requests', auth, rbac.checkTourAccess(['admin', 'editor']), joinRequestController.getTourRequests);
router.patch('/requests/:requestId', auth, rbac.checkTourAccess(['admin', 'editor']), joinRequestController.handleJoinRequest);

router.get('/:id', auth, rbac.checkTourAccess(['admin', 'editor', 'viewer']), tourController.getTourDetails);
router.post('/:tourId/add-member', auth, rbac.checkTourAccess(['admin', 'editor']), tourController.addMember);
router.post('/delete', auth, rbac.checkTourAccess(['admin']), tourController.deleteTour);
router.post('/remove-member', auth, rbac.checkTourAccess(['admin', 'editor']), tourController.removeMember);
router.patch('/:tourId/members/:userId/role', auth, rbac.checkTourAccess(['admin']), tourController.updateMemberRole);
router.post('/:tourId/members/:userId/retroactive-split', auth, rbac.checkTourAccess(['admin', 'editor']), tourController.retroactiveSplit);

module.exports = router;
