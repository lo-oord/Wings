import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_failure.dart';
import '../../data/models/anime.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.items = const <Anime>[],
    this.total,
    this.hasMore = false,
    this.page = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.hasSearched = false,
  });

  final String query;
  final List<Anime> items;
  final int? total;
  final bool hasMore;
  final int page;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final bool hasSearched;

  bool get isEmptyResult =>
      hasSearched && !loading && error == null && items.isEmpty;

  SearchState copyWith({
    String? query,
    List<Anime>? items,
    int? total,
    bool? hasMore,
    int? page,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    bool? hasSearched,
  }) {
    return SearchState(
      query: query ?? this.query,
      items: items ?? this.items,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

class SearchController extends Notifier<SearchState> {
  Timer? _debounce;
  CancelToken? _cancelToken;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancelToken?.cancel();
    });
    return const SearchState();
  }

  void onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _cancelToken?.cancel();
      state = SearchState(query: value);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> submit(String value) async {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) return;
    await ref.read(libraryProvider.notifier).addSearch(query);
    await _search(query);
  }

  Future<void> retry() => _search(state.query);

  Future<void> _search(String query) async {
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    state = state.copyWith(
      query: query,
      loading: true,
      clearError: true,
      items: const <Anime>[],
      hasMore: false,
      page: 0,
    );
    try {
      final page = await ref
          .read(animeRepositoryProvider)
          .search(query, cancelToken: token);
      if (token.isCancelled) return;
      state = state.copyWith(
        items: page.items,
        total: page.total,
        hasMore: page.hasMore,
        page: page.page,
        loading: false,
        hasSearched: true,
      );
    } on Object catch (error) {
      if (token.isCancelled) return;
      state = state.copyWith(
        loading: false,
        hasSearched: true,
        error: error is AppFailure ? error : AppFailure.from(error),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (!current.hasMore || current.loadingMore || current.loading) return;
    state = current.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(animeRepositoryProvider)
          .search(current.query, page: current.page + 1);
      state = state.copyWith(
        items: <Anime>[...current.items, ...page.items],
        hasMore: page.hasMore,
        page: page.page,
        loadingMore: false,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loadingMore: false,
        error: error is AppFailure ? error : AppFailure.from(error),
      );
    }
  }

  void clear() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    state = const SearchState();
  }
}

final searchProvider = NotifierProvider<SearchController, SearchState>(
  SearchController.new,
);
