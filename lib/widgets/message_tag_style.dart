import 'package:flutter/material.dart';
import '../services/workspace_chat_service.dart';
import '../theme/app_theme.dart';

/// The one place a tag turns into colour. Both palettes already carry a
/// light-correct and a dark-correct version of each of these, so a red bubble
/// is readable on white and on navy without a second table of exceptions.
({Color ink, Color bg}) tagColours(MessageTag tag) => switch (tag) {
      MessageTag.pending => (ink: AppColors.amber, bg: AppColors.amberBg),
      MessageTag.invoice => (ink: AppColors.green, bg: AppColors.greenBg),
      MessageTag.urgent => (ink: AppColors.red, bg: AppColors.redBg),
      MessageTag.normal => (ink: AppColors.primary, bg: AppColors.blueBg),
    };

String tagLabel(MessageTag tag) => switch (tag) {
      MessageTag.pending => 'Outstanding',
      MessageTag.invoice => 'Invoice',
      MessageTag.urgent => 'Needs a reply',
      MessageTag.normal => 'Message',
    };

IconData tagIcon(MessageTag tag) => switch (tag) {
      MessageTag.pending => Icons.schedule_outlined,
      MessageTag.invoice => Icons.receipt_long_outlined,
      MessageTag.urgent => Icons.priority_high,
      MessageTag.normal => Icons.chat_bubble_outline,
    };
