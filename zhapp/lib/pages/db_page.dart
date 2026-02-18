import 'package:flutter/material.dart';

class DbPage extends StatelessWidget {
  final List<String> texts;
  final Function(int) onDelete;

  const DbPage({super.key, required this.texts, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (texts.isEmpty) {
      return const Center(child: Text('No saved texts'));
    }
    return ListView.builder(
      itemCount: texts.length,
      itemBuilder: (context, i) => Dismissible(
        key: Key(texts[i]),
        direction: DismissDirection.endToStart,
        onDismissed: (direction) {
          onDelete(i);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Text deleted')));
        },
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16.0),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: ListTile(leading: Text('${i + 1}'), title: Text(texts[i])),
      ),
    );
  }
}
