import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import '../utils/note_utils.dart';

enum HomeViewType { list, kanban }

class NoteProvider extends ChangeNotifier {
  List<Note> _allNotes = [];
  String _searchQuery = '';
  String _selectedLabel = 'Tất cả';
  String _viewMode = 'ALL'; // ALL, MY, SHARED
  String _sortBy = 'date_desc'; // date_desc, date_asc, priority_desc, title_asc
  HomeViewType _homeViewType = HomeViewType.list;

  // Advanced Filters
  String filterCreator = '';
  String filterAssignee = '';
  DateTime? filterCreatedDate;
  DateTime? filterDeadline;
  bool? filterHasAttachments;
  String filterTodoStatus = 'all';
  String filterPriority = 'all';
  String filterNoteType = 'all';
  bool? filterIsPinned;
  bool? filterHasReminder;

  List<Note> _notes = [];
  bool _isLoading = false;
  StreamSubscription? _notesSubscription;
  StreamSubscription<User?>? _authSubscription;
  int _animationTrigger = 0;



  // Getters
  List<Note> get notes => _notes;
  List<Note> get allNotes => _allNotes;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedLabel => _selectedLabel;
  String get viewMode => _viewMode;
  String get sortBy => _sortBy;
  HomeViewType get homeViewType => _homeViewType;
  int get animationTrigger => _animationTrigger;

  void triggerAnimation() {
    _animationTrigger++;
    notifyListeners();
  }

  void setViewType(HomeViewType type) {
    _homeViewType = type;
    notifyListeners();
  }

  NoteProvider() {
    _init();
  }

  void _init() {
    _loadNotes();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _loadNotes();
    });
  }

  void _loadNotes() {
    _isLoading = true;
    refresh();

    _notesSubscription?.cancel();
    
    // Default to watching ALL my accessible notes
    _notesSubscription = FirebaseService.getAllMyNotesStream().listen((notes) {
      _allNotes = notes;
      final wasLoading = _isLoading;
      _isLoading = false;
      if (wasLoading) {
        _animationTrigger++;
      }
      refresh();
    }, onError: (e) {
      _isLoading = false;
      refresh();
    });
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    refresh();
  }

  void setSelectedLabel(String label) {
    _selectedLabel = label;
    refresh();
  }

  void setViewMode(String mode) {
    _viewMode = mode;
    // When switching modes, we might want to reload or just filter differently
    refresh();
  }

  void setSortBy(String sort) {
    _sortBy = sort;
    refresh();
  }

  void resetFilters() {
    filterCreator = '';
    filterAssignee = '';
    filterCreatedDate = null;
    filterDeadline = null;
    filterHasAttachments = null;
    filterTodoStatus = 'all';
    filterPriority = 'all';
    filterNoteType = 'all';
    filterIsPinned = null;
    filterHasReminder = null;
    refresh();
  }

  void refresh() {
    _filterNotes();
  }

  void _filterNotes() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final myUid = FirebaseService.currentUid;

    var filtered = _allNotes.where((note) {
      // Basic Search
      final matchesSearch = note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          note.content.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      // Label Filter
      if (_selectedLabel != 'Tất cả' && note.label != _selectedLabel) return false;

      // View Mode Filter
      final creatorUid = note.userId.trim();
      final creatorEmail = note.createdByEmail.toLowerCase().trim();
      
      // Check if it's a "Ghost" note (no valid owner info)
      final isGhost = creatorUid.isEmpty || creatorUid == 'null' || creatorUid == 'undefined' ||
                      creatorEmail.isEmpty || creatorEmail == 'null';
                      
      final isMyNote = isGhost || 
                       (creatorUid == myUid && myUid.isNotEmpty) || 
                       (creatorEmail == myEmail && myEmail.isNotEmpty);

      if (_viewMode == 'MY' && (!isMyNote || note.groupId.isNotEmpty)) {
        return false;
      }
      if (_viewMode == 'SHARED') {
        if (isMyNote || note.groupId.isNotEmpty) {
          return false;
        }
      }
      if (_viewMode == 'ASSIGNED') {
        final isAssignedToMe = note.assignedTo.contains(myEmail) || 
                               note.todos.any((t) => t.assigneeEmail.toLowerCase().trim() == myEmail);
        if (!isAssignedToMe) return false;
      }

      // Advanced Filters
      if (filterCreator.isNotEmpty && 
          !note.createdByEmail.toLowerCase().contains(filterCreator.toLowerCase()) &&
          !note.createdByName.toLowerCase().contains(filterCreator.toLowerCase())) {
        return false;
      }

      if (filterAssignee.isNotEmpty && 
          (note.groupId.isEmpty || !note.todos.any((t) => 
            t.assigneeEmail.toLowerCase().contains(filterAssignee.toLowerCase()) ||
            t.assigneeName.toLowerCase().contains(filterAssignee.toLowerCase())))) {
        return false;
      }

      if (filterPriority != 'all' && note.priority != filterPriority) return false;
      
      if (filterNoteType != 'all') {
        if (filterNoteType == 'todo' && !note.isTodo) return false;
        if (filterNoteType == 'note' && note.isTodo) return false;
      }

      if (filterIsPinned != null && note.isPinnedByUser != filterIsPinned) return false;

      return true;
    }).toList();

    // Sorting
    filtered.sort((a, b) {
      // Pinned notes ALWAYS go to the top
      if (a.isPinnedByUser != b.isPinnedByUser) {
        return a.isPinnedByUser ? -1 : 1;
      }

      switch (_sortBy) {
        case 'date_desc':
          return b.date.compareTo(a.date);
        case 'date_asc':
          return a.date.compareTo(b.date);
        case 'priority_desc':
          return NotePriority.weight(b.priority).compareTo(NotePriority.weight(a.priority));
        case 'title_asc':
          return NoteUtils.removeDiacritics(a.title).compareTo(NoteUtils.removeDiacritics(b.title));
        default:
          return 0;
      }
    });

    _notes = filtered;
    notifyListeners();
  }

  Future<void> dismissOverdueTodo(String key) async {
    await AppState.dismissOverdueTodo(key);
    notifyListeners();
  }

  @override
  void dispose() {
    _notesSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
