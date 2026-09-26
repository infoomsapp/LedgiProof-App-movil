import 'package:flutter/material.dart';
import '../services/invoice_service.dart';
import '../theme/app_theme.dart';

/// One editable invoice line (description, qty, price, discount, tax). Same
/// fields and behaviour as the editor inside the invoice compose screen, shared
/// here so recurring invoices edit their lines the same way.
class InvoiceItemEditor extends StatelessWidget {
  final DraftItem item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const InvoiceItemEditor({
    super.key,
    required this.item,
    required this.onChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.description,
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                      labelText: 'Description', isDense: true),
                  onChanged: (v) {
                    item.description = v;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.close,
                    size: 18,
                    color: onRemove == null
                        ? AppColors.border
                        : AppColors.inkSubtle),
                tooltip: 'Remove this line',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.quantity == 1
                      ? '1'
                      : item.quantity.toStringAsFixed(2),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration:
                      const InputDecoration(labelText: 'Qty', isDense: true),
                  onChanged: (v) {
                    item.quantity = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue:
                      item.unitPrice == 0 ? '' : item.unitPrice.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                      labelText: 'Unit price', isDense: true),
                  onChanged: (v) {
                    item.unitPrice = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 78,
                child: Text(
                  '\$${item.lineTotal.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          const SizedBox(height: 8),
          // Optional. Left at 0 the line keeps the database defaults, exactly
          // as on the web when these fields are not touched.
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.discountPct == 0
                      ? ''
                      : item.discountPct.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                      labelText: 'Discount %', isDense: true),
                  onChanged: (v) {
                    item.discountPct =
                        (double.tryParse(v) ?? 0).clamp(0, 100).toDouble();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue:
                      item.taxRate == 0 ? '' : item.taxRate.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration:
                      const InputDecoration(labelText: 'Tax %', isDense: true),
                  onChanged: (v) {
                    item.taxRate =
                        (double.tryParse(v) ?? 0).clamp(0, 100).toDouble();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 84),
            ],
          ),
        ],
      ),
    );
  }
}
