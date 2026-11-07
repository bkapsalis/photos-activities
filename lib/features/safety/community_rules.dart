import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/contact.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';

/// The rules everyone agrees to by signing in: zero tolerance for
/// objectionable content and abusive users, as App Store guideline 1.2
/// requires, and how to reach the moderator.
class CommunityRulesScreen extends StatelessWidget {
  const CommunityRulesScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const CommunityRulesScreen()));

  static const rules = [
    'No nudity or sexual content.',
    'No hate speech, slurs or hate symbols.',
    'No violence, threats, or urging anyone to harm themselves or others.',
    "No bullying, harassment, or sharing someone's private details.",
    'No spam or scams.',
  ];

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: 14.5, height: 1.5);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Community rules'),
        backgroundColor: AppColors.background,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Bill's Bay Area is for sharing fun places to visit. To keep "
                  'it welcoming for everyone, families included:',
                  style: body,
                ),
                const SizedBox(height: 12),
                for (final rule in rules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3, right: 10),
                          child: Icon(
                            Icons.block,
                            size: 16,
                            color: AppColors.heartRed,
                          ),
                        ),
                        Expanded(child: Text(rule, style: body)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'There is zero tolerance for objectionable content or '
                  'abusive users. New photos, comments and chat messages may '
                  'be checked by an AI filter, and a moderator reviews every '
                  'report within 24 hours. Anything that breaks these rules '
                  'is removed, and anyone who breaks them can be banned.',
                  style: body,
                ),
                const SizedBox(height: 12),
                const Text(
                  'See something that breaks the rules? Tap ⋯ on the photo, '
                  'comment or message and choose Report. To stop seeing '
                  "someone's posts, choose Block.",
                  style: body,
                ),
                const SizedBox(height: 20),
                const ContactLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Contact: bkapsalis@gmail.com", opening the reader's email app.
class ContactLink extends StatelessWidget {
  const ContactLink({super.key});

  static Future<void> open() => launchUrl(
    Uri.parse(
      'mailto:$contactEmail?subject=${Uri.encodeComponent("Bill's Bay Area")}',
    ),
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.email_outlined, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Contact: $contactEmail',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The privacy policy, a page on this environment's website (web/privacy.html).
/// Apple wants it reachable from inside the app, not only from the store
/// listing.
class PrivacyPolicy {
  const PrivacyPolicy._();

  static Uri get url => Uri.parse('${EnvConfig.instance.website}/privacy');

  static Future<void> open() => launchUrl(url);
}

/// Under the sign-in buttons: signing in, or continuing as a guest, is
/// agreeing to the rules.
class RulesAgreementNote extends StatelessWidget {
  const RulesAgreementNote({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    const link = TextStyle(
      fontSize: 12,
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('By continuing, you agree to the ', style: style),
        InkWell(
          onTap: () => CommunityRulesScreen.show(context),
          child: const Text('Community rules', style: link),
        ),
        const Text(
          ': no objectionable content and no abusive behavior. ',
          style: style,
        ),
        const InkWell(
          onTap: PrivacyPolicy.open,
          child: Text('Privacy policy', style: link),
        ),
      ],
    );
  }
}
