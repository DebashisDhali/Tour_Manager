import '../../../data/local/app_database.dart';
import '../settlement_calculator.dart';
import 'base_calculator.dart';
import 'tour_calculator.dart';

/// Specialized calculator for Parties.
/// Currently uses the same logic as Tour but separated for future customization and 100% accuracy.
class PartySettlementCalculator extends TourSettlementCalculator {
  // Logic is inherited from TourSettlementCalculator as they currently share the same split-based model.
  // Add Party-specific calculation refinements here if needed.
}
