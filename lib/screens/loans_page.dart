import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../state/library.dart';
import '../widgets/cover.dart';
import 'item_detail_screen.dart';

class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final loans = library.loans;
    final theme = Theme.of(context);

    if (loans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.outbox, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('Aucun prêt en cours', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Ouvrez une fiche et touchez « Prêter » pour savoir qui a vos disques et vos livres.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: loans.length,
      itemBuilder: (context, i) {
        final item = loans[i];
        final days = item.loanDate == null ? null : now.difference(item.loanDate!).inDays;
        final since = item.loanDate == null
            ? ''
            : ' · ${DateFormat.yMMMd('fr').format(item.loanDate!)}'
                  '${days! >= 1 ? ' ($days j)' : ''}';
        return ListTile(
          leading: Cover(item: item, width: 40),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.loanedTo}$since', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: !library.canEdit
              ? null
              : TextButton(
                  onPressed: () async {
                    await library.giveBack(item);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('« ${item.title} » est rendu'),
                          action: SnackBarAction(label: 'Annuler', onPressed: () => library.save(item)),
                        ),
                      );
                    }
                  },
                  child: const Text('Rendu'),
                ),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(itemId: item.id!))),
        );
      },
    );
  }
}
