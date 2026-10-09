import 'dart:convert';

import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/products.dart';

class ProductsRepository {
  ProductsRepository(this._api);
  final ApiClient _api;

  Future<List<Product>> list({
    String? q,
    String? category,
    bool lowStock = false,
    String? sort,
    String? barcode,
    bool includeInactive = false,
  }) async => (await _api.get(
    '/v5/products',
    query: {
      'q': q,
      'category': category,
      'lowStock': lowStock ? 'true' : null,
      'sort': sort,
      'barcode': barcode,
      'includeInactive': includeInactive ? 'true' : null,
    },
  )).list.map(Product.fromJson).toList();

  Future<Product> get(String id) async =>
      Product.fromJson((await _api.get('/v5/products/$id')).map);
  Future<Product> create(Json body) async =>
      Product.fromJson((await _api.post('/v5/products', body: body)).map);
  Future<Product> update(String id, Json body) async =>
      Product.fromJson((await _api.patch('/v5/products/$id', body: body)).map);
  Future<void> delete(String id) async => _api.delete('/v5/products/$id');
  Future<List<String>> categories() async =>
      (await _api.get('/v5/products/categories')).stringList;
  Future<List<String>> damageReasons() async =>
      (await _api.get('/v5/products/damage-reasons')).stringList;

  Future<Product> startTracking(
    String id,
    int openingCount, {
    int? lowStockThreshold,
  }) async => Product.fromJson(
    (await _api.post(
      '/v5/products/$id/stock/track',
      body: compact({
        'openingCount': openingCount,
        'lowStockThreshold': lowStockThreshold,
      }),
    )).map,
  );
  Future<Product> stopTracking(String id) async =>
      Product.fromJson((await _api.post('/v5/products/$id/stock/untrack')).map);
  Future<Product> receive(
    String id,
    int quantity, {
    double? totalCost,
    bool logAsExpense = false,
    String? notes,
  }) async => Product.fromJson(
    (await _api.post(
      '/v5/products/$id/stock/receive',
      body: compact({
        'quantity': quantity,
        'totalCost': totalCost,
        'logAsExpense': logAsExpense,
        'notes': notes,
      }),
    )).map,
  );
  Future<Product> damage(String id, int quantity, String reason) async =>
      Product.fromJson(
        (await _api.post(
          '/v5/products/$id/stock/damage',
          body: {'quantity': quantity, 'reason': reason},
        )).map,
      );
  Future<Product> correct(String id, int newCount, String reason) async =>
      Product.fromJson(
        (await _api.post(
          '/v5/products/$id/stock/correct',
          body: {'newCount': newCount, 'reason': reason},
        )).map,
      );
  Future<List<StockEntry>> history(String id) async =>
      (await _api.get('/v5/products/$id/stock/history')).list
          .map(StockEntry.fromJson)
          .toList();

  // ---- sales ----
  Future<ApiResponse> sales(int page, int limit, Json q) => _api.get(
    '/v5/product-sales',
    query: {...q, 'page': page, 'limit': limit},
  );
  Future<Sale> createSale(Json body) async =>
      Sale.fromJson((await _api.post('/v5/product-sales', body: body)).map);
  Future<void> deleteSale(String id) async =>
      _api.delete('/v5/product-sales/$id');

  static Map<String, dynamic> photo(List<int> bytes, String contentType) => {
    'data': base64Encode(bytes),
    'contentType': contentType,
  };
}
