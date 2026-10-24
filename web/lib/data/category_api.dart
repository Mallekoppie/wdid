import 'package:grpc/grpc_or_grpcweb.dart';

import '../models/link_ref.dart';
import '../models/taxonomy.dart';
import '../src/generated/categories.pbgrpc.dart' as generated;
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// A user-facing category failure, with the field the service rejected.
class CategoryFailure extends ServiceFailure {
  const CategoryFailure(super.message, {super.field});
}

/// The taxonomy operations the Settings screen consumes. Reads and writes are
/// per account; the service derives the account from the bearer token.
abstract class CategoryApi {
  Future<List<Category>> listCategories();

  Future<List<Subcategory>> listSubcategories({String categoryId = ''});

  Future<Category> createCategory({
    required String name,
    required CategoryRole role,
    String color = '',
    int sortOrder = 0,
  });

  Future<Category> updateCategory(Category category);

  Future<Category> archiveCategory(String id, {bool archived = true});

  Future<void> deleteCategory(String id);

  Future<Subcategory> createSubcategory({
    required String categoryId,
    required String name,
    SubcategoryStatus status = SubcategoryStatus.active,
    String description = '',
    int progress = 0,
    String targetOutcome = '',
    String targetDate = '',
    List<LinkRef> links = const [],
    int sortOrder = 0,
  });

  Future<Subcategory> updateSubcategory(Subcategory subcategory);

  Future<Subcategory> archiveSubcategory(String id, {bool archived = true});

  Future<void> deleteSubcategory(String id);
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class CategoryRpc {
  Future<generated.ListCategoriesResponse> listCategories(
    generated.ListCategoriesRequest request,
  );

  Future<generated.ListSubcategoriesResponse> listSubcategories(
    generated.ListSubcategoriesRequest request,
  );

  Future<generated.CreateCategoryResponse> createCategory(
    generated.CreateCategoryRequest request,
  );

  Future<generated.UpdateCategoryResponse> updateCategory(
    generated.UpdateCategoryRequest request,
  );

  Future<generated.ArchiveCategoryResponse> archiveCategory(
    generated.ArchiveCategoryRequest request,
  );

  Future<generated.DeleteCategoryResponse> deleteCategory(
    generated.DeleteCategoryRequest request,
  );

  Future<generated.CreateSubcategoryResponse> createSubcategory(
    generated.CreateSubcategoryRequest request,
  );

  Future<generated.UpdateSubcategoryResponse> updateSubcategory(
    generated.UpdateSubcategoryRequest request,
  );

  Future<generated.ArchiveSubcategoryResponse> archiveSubcategory(
    generated.ArchiveSubcategoryRequest request,
  );

  Future<generated.DeleteSubcategoryResponse> deleteSubcategory(
    generated.DeleteSubcategoryRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcCategoryRpc implements CategoryRpc {
  GrpcCategoryRpc({
    generated.CategoryServiceClient? client,
    String? Function()? token,
  }) : _client =
           client ??
           generated.CategoryServiceClient(
             openAppChannel(),
             interceptors: [bearerInterceptor(token ?? (() => null))],
           );

  final generated.CategoryServiceClient _client;

  @override
  Future<generated.ListCategoriesResponse> listCategories(
    generated.ListCategoriesRequest request,
  ) => _client.listCategories(request);

  @override
  Future<generated.ListSubcategoriesResponse> listSubcategories(
    generated.ListSubcategoriesRequest request,
  ) => _client.listSubcategories(request);

  @override
  Future<generated.CreateCategoryResponse> createCategory(
    generated.CreateCategoryRequest request,
  ) => _client.createCategory(request);

  @override
  Future<generated.UpdateCategoryResponse> updateCategory(
    generated.UpdateCategoryRequest request,
  ) => _client.updateCategory(request);

  @override
  Future<generated.ArchiveCategoryResponse> archiveCategory(
    generated.ArchiveCategoryRequest request,
  ) => _client.archiveCategory(request);

  @override
  Future<generated.DeleteCategoryResponse> deleteCategory(
    generated.DeleteCategoryRequest request,
  ) => _client.deleteCategory(request);

  @override
  Future<generated.CreateSubcategoryResponse> createSubcategory(
    generated.CreateSubcategoryRequest request,
  ) => _client.createSubcategory(request);

  @override
  Future<generated.UpdateSubcategoryResponse> updateSubcategory(
    generated.UpdateSubcategoryRequest request,
  ) => _client.updateSubcategory(request);

  @override
  Future<generated.ArchiveSubcategoryResponse> archiveSubcategory(
    generated.ArchiveSubcategoryRequest request,
  ) => _client.archiveSubcategory(request);

  @override
  Future<generated.DeleteSubcategoryResponse> deleteSubcategory(
    generated.DeleteSubcategoryRequest request,
  ) => _client.deleteSubcategory(request);
}

/// Category management over Connect/gRPC-Web.
class GrpcCategoryApi implements CategoryApi {
  GrpcCategoryApi({CategoryRpc? rpc}) : _rpc = rpc ?? GrpcCategoryRpc();

  static const _pageSize = 200;

  final CategoryRpc _rpc;

  @override
  Future<List<Category>> listCategories() async {
    try {
      return [
        for (final response in await _pages(
          (token) => _rpc.listCategories(
            generated.ListCategoriesRequest(
              pageSize: _pageSize,
              pageToken: token,
            ),
          ),
          (response) => response.nextPageToken,
        ))
          ...response.categories.map(_category),
      ];
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<Subcategory>> listSubcategories({String categoryId = ''}) async {
    try {
      return [
        for (final response in await _pages(
          (token) => _rpc.listSubcategories(
            generated.ListSubcategoriesRequest(
              categoryId: categoryId,
              pageSize: _pageSize,
              pageToken: token,
            ),
          ),
          (response) => response.nextPageToken,
        ))
          ...response.subcategories.map(_subcategory),
      ];
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  Future<List<T>> _pages<T>(
    Future<T> Function(String token) fetch,
    String Function(T response) nextToken,
  ) async {
    final pages = <T>[];
    var token = '';
    do {
      final page = await fetch(token);
      pages.add(page);
      token = nextToken(page);
    } while (token.isNotEmpty);
    return pages;
  }

  @override
  Future<Category> createCategory({
    required String name,
    required CategoryRole role,
    String color = '',
    int sortOrder = 0,
  }) async {
    try {
      final response = await _rpc.createCategory(
        generated.CreateCategoryRequest(
          name: name,
          role: _roleToProto(role),
          color: color,
          sortOrder: sortOrder,
        ),
      );
      return _category(response.category);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Category> updateCategory(Category category) async {
    try {
      final response = await _rpc.updateCategory(
        generated.UpdateCategoryRequest(
          id: category.id,
          name: category.name,
          color: category.color,
          sortOrder: category.sortOrder,
        ),
      );
      return _category(response.category);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Category> archiveCategory(String id, {bool archived = true}) async {
    try {
      final response = await _rpc.archiveCategory(
        generated.ArchiveCategoryRequest(id: id, archived: archived),
      );
      return _category(response.category);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    try {
      await _rpc.deleteCategory(generated.DeleteCategoryRequest(id: id));
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Subcategory> createSubcategory({
    required String categoryId,
    required String name,
    SubcategoryStatus status = SubcategoryStatus.active,
    String description = '',
    int progress = 0,
    String targetOutcome = '',
    String targetDate = '',
    List<LinkRef> links = const [],
    int sortOrder = 0,
  }) async {
    try {
      final response = await _rpc.createSubcategory(
        generated.CreateSubcategoryRequest(
          categoryId: categoryId,
          name: name,
          description: description,
          status: _statusToProto(status),
          progress: progress,
          targetOutcome: targetOutcome,
          targetDate: targetDate,
          links: _linksToProto(links),
          sortOrder: sortOrder,
        ),
      );
      return _subcategory(response.subcategory);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Subcategory> updateSubcategory(Subcategory subcategory) async {
    try {
      final response = await _rpc.updateSubcategory(
        generated.UpdateSubcategoryRequest(
          id: subcategory.id,
          name: subcategory.name,
          description: subcategory.description,
          status: _statusToProto(subcategory.status),
          progress: subcategory.progress,
          targetOutcome: subcategory.targetOutcome,
          targetDate: subcategory.targetDate,
          links: _linksToProto(subcategory.links),
          sortOrder: subcategory.sortOrder,
        ),
      );
      return _subcategory(response.subcategory);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Subcategory> archiveSubcategory(
    String id, {
    bool archived = true,
  }) async {
    try {
      final response = await _rpc.archiveSubcategory(
        generated.ArchiveSubcategoryRequest(id: id, archived: archived),
      );
      return _subcategory(response.subcategory);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteSubcategory(String id) async {
    try {
      await _rpc.deleteSubcategory(generated.DeleteSubcategoryRequest(id: id));
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  Category _category(generated.Category category) => Category(
    id: category.id,
    name: category.name,
    role: _roleFromProto(category.role),
    color: category.color,
    sortOrder: category.sortOrder,
    archived: category.archived,
    createdAt: category.createdAt.toDateTime(),
    updatedAt: category.updatedAt.toDateTime(),
  );

  Subcategory _subcategory(generated.Subcategory subcategory) => Subcategory(
    id: subcategory.id,
    categoryId: subcategory.categoryId,
    name: subcategory.name,
    description: subcategory.description,
    status: _statusFromProto(subcategory.status),
    progress: subcategory.progress,
    targetOutcome: subcategory.targetOutcome,
    targetDate: subcategory.targetDate,
    links: subcategory.links
        .map((link) => LinkRef(label: link.label, url: link.url))
        .toList(),
    sortOrder: subcategory.sortOrder,
    archived: subcategory.archived,
    createdAt: subcategory.createdAt.toDateTime(),
    updatedAt: subcategory.updatedAt.toDateTime(),
  );

  CategoryFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to manage categories.',
      failedPrecondition: 'That category is referenced by existing work and can only be archived.',
      notFound: 'That category no longer exists.',
    );
    return CategoryFailure(text.message, field: text.field);
  }
}

CategoryRole _roleFromProto(generated.CategoryRole role) {
  switch (role) {
    case generated.CategoryRole.CATEGORY_ROLE_INITIATIVE:
      return CategoryRole.initiative;
    case generated.CategoryRole.CATEGORY_ROLE_SUPPORT:
      return CategoryRole.support;
    default:
      return CategoryRole.other;
  }
}

generated.CategoryRole _roleToProto(CategoryRole role) {
  switch (role) {
    case CategoryRole.initiative:
      return generated.CategoryRole.CATEGORY_ROLE_INITIATIVE;
    case CategoryRole.support:
      return generated.CategoryRole.CATEGORY_ROLE_SUPPORT;
    case CategoryRole.other:
      return generated.CategoryRole.CATEGORY_ROLE_OTHER;
  }
}

SubcategoryStatus _statusFromProto(generated.SubcategoryStatus status) {
  switch (status) {
    case generated.SubcategoryStatus.SUBCATEGORY_STATUS_PLANNED:
      return SubcategoryStatus.planned;
    case generated.SubcategoryStatus.SUBCATEGORY_STATUS_BLOCKED:
      return SubcategoryStatus.blocked;
    case generated.SubcategoryStatus.SUBCATEGORY_STATUS_DONE:
      return SubcategoryStatus.done;
    case generated.SubcategoryStatus.SUBCATEGORY_STATUS_ARCHIVED:
      return SubcategoryStatus.archived;
    default:
      return SubcategoryStatus.active;
  }
}

generated.SubcategoryStatus _statusToProto(SubcategoryStatus status) {
  switch (status) {
    case SubcategoryStatus.planned:
      return generated.SubcategoryStatus.SUBCATEGORY_STATUS_PLANNED;
    case SubcategoryStatus.active:
      return generated.SubcategoryStatus.SUBCATEGORY_STATUS_ACTIVE;
    case SubcategoryStatus.blocked:
      return generated.SubcategoryStatus.SUBCATEGORY_STATUS_BLOCKED;
    case SubcategoryStatus.done:
      return generated.SubcategoryStatus.SUBCATEGORY_STATUS_DONE;
    case SubcategoryStatus.archived:
      return generated.SubcategoryStatus.SUBCATEGORY_STATUS_ARCHIVED;
  }
}

List<generated.Link> _linksToProto(List<LinkRef> links) => [
  for (final link in links) generated.Link(label: link.label, url: link.url),
];
