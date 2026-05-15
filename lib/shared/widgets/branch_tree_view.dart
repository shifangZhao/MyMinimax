import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../features/chat/domain/branch_info.dart';

class BranchTreeView extends StatelessWidget {

  const BranchTreeView({
    required this.branches, required this.activeBranchId, required this.onSwitchBranch, super.key,
    this.onNewBranch,
    this.onDeleteBranch,
  });
  final List<BranchInfo> branches;
  final String activeBranchId;
  final void Function(String branchId) onSwitchBranch;
  final VoidCallback? onNewBranch;
  final void Function(String branchId)? onDeleteBranch;

  static void show({
    required BuildContext context,
    required List<BranchInfo> branches,
    required String activeBranchId,
    required void Function(String branchId) onSwitchBranch,
    VoidCallback? onNewBranch,
    void Function(String branchId)? onDeleteBranch,
  }) {
    showModalBottomSheet(
      context: context,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (ctx) => BranchTreeView(
        branches: branches,
        activeBranchId: activeBranchId,
        onSwitchBranch: onSwitchBranch,
        onNewBranch: onNewBranch,
        onDeleteBranch: onDeleteBranch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(PixelTheme.radiusLg)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree,
                    size: 20,
                    color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '对话分支',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                    ),
                  ),
                  const Spacer(),
                  if (onNewBranch != null)
                    _SmallButton(
                      icon: Icons.add,
                      label: '新分支',
                      onTap: onNewBranch!,
                    ),
                ],
              ),
            ),
            const Divider(),
            // Branch list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: branches.length,
                itemBuilder: (ctx, i) {
                  final branch = branches[i];
                  final isActive = branch.id == activeBranchId;
                  return _BranchTile(
                    branch: branch,
                    isActive: isActive,
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      if (!isActive) onSwitchBranch(branch.id);
                    },
                    onDelete: onDeleteBranch != null
                        ? () {
                            Navigator.pop(context);
                            onDeleteBranch!(branch.id);
                          }
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {

  const _SmallButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (isDark ? PixelTheme.darkPrimary : PixelTheme.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {

  const _BranchTile({
    required this.branch,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    this.onDelete,
  });
  final BranchInfo branch;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分支', style: TextStyle(fontFamily: 'monospace')),
        content: Text('确定要删除分支"${branch.name ?? 'branch'}"吗？\n该分支的所有消息将被永久删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary).withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
            border: isActive
                ? Border.all(
                    color: (isDark ? PixelTheme.darkPrimary : PixelTheme.primary).withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              // Branch node dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary)
                      : (isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder),
                  border: Border.all(
                    color: isActive
                        ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary)
                        : (isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder),
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          branch.name ?? 'branch',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive
                                ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary)
                                : (isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isDark ? PixelTheme.darkPrimary : PixelTheme.primary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '当前',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9,
                                color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${branch.messageCount} 条消息',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isActive)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                ),
              if (onDelete != null)
                GestureDetector(
                  onTap: () => _confirmDelete(context),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}