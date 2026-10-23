import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/src/generated/categories.pbgrpc.dart' as generated;

class FakeCategoryRpc implements CategoryRpc {
  Object? error;

  generated.ListCategoriesResponse listResponse =
      generated.ListCategoriesResponse();
  generated.ListSubcategoriesResponse subcategoryResponse =
      generated.ListSubcategoriesResponse();
  generated.Category categoryResponse = generated.Category();
  generated.Subcategory subcategory = generated.Subcategory();

  generated.CreateCategoryRequest? createRequest;
  generated.UpdateCategoryRequest? updateRequest;
  generated.ArchiveCategoryRequest? archiveRequest;
  generated.CreateSubcategoryRequest? createSubcategoryRequest;
  generated.UpdateSubcategoryRequest? updateSubcategoryRequest;

  void _maybeFail() {
    if (error != null) throw error!;
  }

  @override
  Future<generated.ListCategoriesResponse> listCategories(
    generated.ListCategoriesRequest request,
  ) async {
    _maybeFail();
    return listResponse;
  }

  @override
  Future<generated.ListSubcategoriesResponse> listSubcategories(
    generated.ListSubcategoriesRequest request,
  ) async {
    _maybeFail();
    return subcategoryResponse;
  }

  @override
  Future<generated.CreateCategoryResponse> createCategory(
    generated.CreateCategoryRequest request,
  ) async {
    createRequest = request;
    _maybeFail();
    return generated.CreateCategoryResponse(category: categoryResponse);
  }

  @override
  Future<generated.UpdateCategoryResponse> updateCategory(
    generated.UpdateCategoryRequest request,
  ) async {
    updateRequest = request;
    _maybeFail();
    return generated.UpdateCategoryResponse(category: categoryResponse);
  }

  @override
  Future<generated.ArchiveCategoryResponse> archiveCategory(
    generated.ArchiveCategoryRequest request,
  ) async {
    archiveRequest = request;
    _maybeFail();
    return generated.ArchiveCategoryResponse(category: categoryResponse);
  }

  @override
  Future<generated.DeleteCategoryResponse> deleteCategory(
    generated.DeleteCategoryRequest request,
  ) async {
    _maybeFail();
    return generated.DeleteCategoryResponse();
  }

  @override
  Future<generated.CreateSubcategoryResponse> createSubcategory(
    generated.CreateSubcategoryRequest request,
  ) async {
    createSubcategoryRequest = request;
    _maybeFail();
    return generated.CreateSubcategoryResponse(subcategory: subcategory);
  }

  @override
  Future<generated.UpdateSubcategoryResponse> updateSubcategory(
    generated.UpdateSubcategoryRequest request,
  ) async {
    updateSubcategoryRequest = request;
    _maybeFail();
    return generated.UpdateSubcategoryResponse(subcategory: subcategory);
  }

  @override
  Future<generated.ArchiveSubcategoryResponse> archiveSubcategory(
    generated.ArchiveSubcategoryRequest request,
  ) async {
    _maybeFail();
    return generated.ArchiveSubcategoryResponse(subcategory: subcategory);
  }

  @override
  Future<generated.DeleteSubcategoryResponse> deleteSubcategory(
    generated.DeleteSubcategoryRequest request,
  ) async {
    _maybeFail();
    return generated.DeleteSubcategoryResponse();
  }
}

generated.Category protoCategory({
  String id = 'cat-1',
  String name = 'Initiatives',
  generated.CategoryRole role = generated.CategoryRole.CATEGORY_ROLE_INITIATIVE,
  String color = '#00696D',
  int sortOrder = 2,
  bool archived = false,
}) {
  final stamp = Timestamp.fromDateTime(DateTime.utc(2026, 10, 23, 8));
  return generated.Category(
    id: id,
    name: name,
    role: role,
    color: color,
    sortOrder: sortOrder,
    archived: archived,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

void main() {
  test('listCategories maps generated categories to the UI model', () async {
    final rpc = FakeCategoryRpc()
      ..listResponse = generated.ListCategoriesResponse(
        categories: [
          protoCategory(),
          protoCategory(
            id: 'cat-2',
            name: 'Support',
            role: generated.CategoryRole.CATEGORY_ROLE_SUPPORT,
            sortOrder: 1,
            archived: true,
          ),
        ],
      );

    final categories = await GrpcCategoryApi(rpc: rpc).listCategories();

    expect(categories, hasLength(2));
    expect(categories.first.id, 'cat-1');
    expect(categories.first.role, CategoryRole.initiative);
    expect(categories.first.color, '#00696D');
    expect(categories.first.sortOrder, 2);
    expect(categories.first.archived, isFalse);
    expect(categories.last.role, CategoryRole.support);
    expect(categories.last.archived, isTrue);
    expect(categories.first.createdAt, DateTime.utc(2026, 10, 23, 8));
  });

  test(
    'createCategory sends the immutable role and returns the created row',
    () async {
      final rpc = FakeCategoryRpc()
        ..categoryResponse = protoCategory(
          id: 'cat-9',
          name: 'Deep work',
          role: generated.CategoryRole.CATEGORY_ROLE_OTHER,
        );

      final created = await GrpcCategoryApi(rpc: rpc).createCategory(
        name: 'Deep work',
        role: CategoryRole.other,
        color: '#112233',
        sortOrder: 4,
      );

      expect(rpc.createRequest!.name, 'Deep work');
      expect(
        rpc.createRequest!.role,
        generated.CategoryRole.CATEGORY_ROLE_OTHER,
      );
      expect(rpc.createRequest!.color, '#112233');
      expect(rpc.createRequest!.sortOrder, 4);
      expect(created.id, 'cat-9');
      expect(created.role, CategoryRole.other);
    },
  );

  test('updateCategory never carries a role', () async {
    final rpc = FakeCategoryRpc()
      ..categoryResponse = protoCategory(id: 'cat-1', name: 'Renamed');
    final existing = Category(
      id: 'cat-1',
      name: 'Old',
      role: CategoryRole.support,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    final updated = await GrpcCategoryApi(rpc: rpc).updateCategory(existing);

    expect(rpc.updateRequest!.id, 'cat-1');
    expect(rpc.updateRequest!.name, 'Old');
    expect(updated.name, 'Renamed');
  });

  test('subcategories round-trip status, progress and links', () async {
    final stamp = Timestamp.fromDateTime(DateTime.utc(2026, 10, 23, 9));
    final rpc = FakeCategoryRpc()
      ..subcategory = generated.Subcategory(
        id: 'sub-1',
        categoryId: 'cat-1',
        name: 'Billing migration',
        status: generated.SubcategoryStatus.SUBCATEGORY_STATUS_BLOCKED,
        progress: 60,
        links: [generated.Link(label: 'Epic', url: 'https://example.com/epic')],
        createdAt: stamp,
        updatedAt: stamp,
      );

    final created = await GrpcCategoryApi(rpc: rpc).createSubcategory(
      categoryId: 'cat-1',
      name: 'Billing migration',
      status: SubcategoryStatus.blocked,
    );

    expect(
      rpc.createSubcategoryRequest!.status,
      generated.SubcategoryStatus.SUBCATEGORY_STATUS_BLOCKED,
    );
    expect(created.categoryId, 'cat-1');
    expect(created.status, SubcategoryStatus.blocked);
    expect(created.progress, 60);
    expect(created.links, hasLength(1));
    expect(created.links.first.label, 'Epic');
    expect(created.links.first.url, 'https://example.com/epic');
  });

  test('validation failures expose the rejected field', () async {
    final rpc = FakeCategoryRpc()
      ..error = GrpcError.invalidArgument(
        'role: must be initiative, support or other',
      );

    expect(
      () =>
          GrpcCategoryApi(rpc: rpc)
              .createCategory(name: 'No role', role: CategoryRole.other),
      throwsA(
        isA<CategoryFailure>()
            .having((failure) => failure.field, 'field', 'role')
            .having(
              (failure) => failure.message,
              'message',
              'role: must be initiative, support or other',
            ),
      ),
    );
  });

  test(
    'archive failures explain that referenced rows must be archived',
    () async {
      final rpc = FakeCategoryRpc()
        ..error = GrpcError.failedPrecondition(
          'category is referenced and cannot be deleted',
        );

      expect(
        () => GrpcCategoryApi(rpc: rpc).deleteCategory('cat-1'),
        throwsA(
          isA<CategoryFailure>().having(
            (failure) => failure.message,
            'message',
            'category is referenced and cannot be deleted',
          ),
        ),
      );
    },
  );
}
