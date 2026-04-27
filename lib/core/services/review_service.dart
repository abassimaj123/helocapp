import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  static const _keyShown = 'review_v2';

  Future<void> requestReview() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyShown) == true) return;
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
      await prefs.setBool(_keyShown, true);
    }
  }
}
