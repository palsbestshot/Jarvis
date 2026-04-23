import 'package:flutter/material.dart';
import '../core/theme.dart';
import './motivation_ring.dart';

class DashboardBubble extends StatelessWidget {
  final String quote;
  final String date;
  final String greeting;
  final int completedTasks;
  final int totalTasks;
  final List<Map<String, dynamic>>? pendingTasks;
  final bool isEvening;
  final Function(String)? onPostponeTask;

  const DashboardBubble({
    super.key,
    required this.quote,
    required this.date,
    required this.greeting,
    required this.completedTasks,
    required this.totalTasks,
    this.pendingTasks,
    this.isEvening = false,
    this.onPostponeTask,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalTasks > 0 ? completedTasks / totalTasks : 0.0;
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      margin: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 16,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: JarvisTheme.pallavAccent.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quote
          Text(
            '"$quote"',
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: JarvisTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          // Date and greeting
          Text(
            date,
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          
          const SizedBox(height: 4),
          
          Text(
            greeting,
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textSecondary,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Motivation ring
          Center(
            child: MotivationRing(
              completed: completedTasks,
              total: totalTasks,
              size: 80,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Task summary
          Text(
            'Tasks: $completedTasks/$totalTasks completed',
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textPrimary,
            ),
          ),
          
          // Evening specific: pending tasks
          if (isEvening && pendingTasks != null && pendingTasks!.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  'Pending tasks:',
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: JarvisTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...pendingTasks!.map((task) {
                  return _buildPendingTaskRow(task);
                }).toList(),
              ],
            ),
          
          // Motivational close
          const SizedBox(height: 16),
          Text(
            _getMotivationalClose(progress),
            style: JarvisTheme.bodySmall.copyWith(
              color: JarvisTheme.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTaskRow(Map<String, dynamic> task) {
    final taskId = task['id']?.toString() ?? '';
    final title = task['title']?.toString() ?? 'Untitled Task';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textPrimary,
              ),
            ),
          ),
          if (onPostponeTask != null)
            IconButton(
              onPressed: () => onPostponeTask!(taskId),
              icon: const Icon(
                Icons.skip_next,
                color: JarvisTheme.pallavAccent,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  String _getMotivationalClose(double progress) {
    final percentage = (progress * 100).round();
    
    if (isEvening) {
      if (percentage == 0) {
        return 'Tomorrow is a new day. Start fresh.';
      } else if (percentage <= 30) {
        return 'Small steps matter. Rest well.';
      } else if (percentage <= 60) {
        return 'Good effort today. Recharge for tomorrow.';
      } else if (percentage < 100) {
        return 'Almost there. Finish strong tomorrow.';
      } else {
        return 'Perfect day. Well earned rest.';
      }
    } else {
      // Morning
      if (percentage == 0) {
        return 'Time to crush it. Get moving.';
      } else if (percentage <= 30) {
        return 'Good start. Don\'t lose momentum.';
      } else if (percentage <= 60) {
        return 'Halfway there. Stay focused.';
      } else if (percentage < 100) {
        return 'Almost there. Finish strong.';
      } else {
        return 'Nailed it. Every single one. 💪';
      }
    }
  }
}