import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Events.dart';

enum Status { uninitialized, authenticated, authenticating, unauthenticated }

class UserState extends ChangeNotifier {
  User? _user;
  Status _status = Status.uninitialized;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance; 
  bool _isLoading = false;
  bool _isLoggedIn = false;
  bool _isSigning = false;

  String _username = '';
  String _aboutMe = '';
  String _profileImageUrl = '';
  String _livesIn = '';
  double _totalDistance = 0.0;
  double _caloriesBurned = 0.0;
  int _stepsTaken = 0;

  UserState() {
    _auth.authStateChanges().listen((User? firebaseUser) async {
      _user = firebaseUser;
      _status = _user == null ? Status.unauthenticated : Status.authenticated;
      if (_user != null) {
        await _fetchUserData();
        _startListeningToEvents(); // Start real-time listening to events
      }
      notifyListeners();
    });
  }
  void updateMyEvents(List<Event> events) {
    _myEvents = events;
    notifyListeners();
  }


  Status get status => _status;
  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSigning => _isSigning;
  bool get isLoggedIn => _isLoggedIn;
  String get username => _username;
  String get aboutMe => _aboutMe;
  String get profileImageUrl => _profileImageUrl;
  String get livesIn => _livesIn;
  double get totalDistance => _totalDistance;
  double get caloriesBurned => _caloriesBurned;
  int get stepsTaken => _stepsTaken;


  List<Event> _myEvents = [];
  StreamSubscription<QuerySnapshot>? _eventSubscription; // Subscription for events


    List<Event> get myEvents => _myEvents;

   // Add this method to cancel Firestore listeners
  Future<void> cancelEventListener() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  void _startListeningToEvents() {
    if (_user != null) {
      _eventSubscription = FirebaseFirestore.instance
          .collection('userInfo')
          .doc(_user!.uid)
          .collection('My Events')
          .snapshots()
          .listen((snapshot) {
        _myEvents = snapshot.docs.map((doc) => Event.fromMap(doc.data() as Map<String, dynamic>)).toList();
        notifyListeners(); // Notify listeners to update the UI
      });
    }
  }


  @override
  void dispose() {
    cancelEventListener(); // Ensure listener is canceled when the state is disposed
    super.dispose();
  }


  Future<void> fetchMyEvents() async {
    if (_user != null) {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('userInfo')
          .doc(_user!.uid)
          .collection('My Events')
          .get();

      _myEvents = snapshot.docs.map((doc) => Event.fromMap(doc.data() as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  
  Future<void> _fetchUserData() async {
    if (_user != null) {
      DocumentSnapshot userDoc = await _db.collection('userInfo').doc(_user!.uid).get();
      Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;
      if (userData != null) {
        _username = userData['username'];
        _aboutMe = userData['About Me'];
        _profileImageUrl = userData.containsKey('profileImageUrl') ? userData['profileImageUrl'] : ''; 
        _livesIn = userData['Lives in'] ?? '';
        _totalDistance = userData['Total Distance'] ?? 0.0;
        if (!userData.containsKey('Steps Taken')) {
               _stepsTaken = 0;
             }
        else 
          _stepsTaken = (userData['Steps Taken']).toInt() ;
        if (!userData.containsKey('Calories Burned')) {
               _caloriesBurned = userData['Calories Burned'] ?? 0.0;
             }
        else
          _caloriesBurned = userData['Calories Burned'] ;
      } else {
        _username = '';
        _aboutMe = '';
        _profileImageUrl = '';
        _livesIn = '';
        _totalDistance = 0.0;
        _caloriesBurned = 0.0;
        _stepsTaken = 0;
      }
      notifyListeners();
    }
  }

  Future<void> updateProfile(String newUsername, String newAboutMe, String newLivesIn, [File? profileImage]) async {
    if (_user != null) {
      String? imageUrl;
      if (profileImage != null) {
        imageUrl = await _uploadProfileImage(profileImage);
      }

      await _db.collection('userInfo').doc(_user!.uid).update({
        'username': newUsername,
        'About Me': newAboutMe,
        'Lives in': newLivesIn,
        if (imageUrl != null) 'profileImageUrl': imageUrl,
      });

      _username = newUsername;
      _aboutMe = newAboutMe;
      _livesIn = newLivesIn;
      if (imageUrl != null) _profileImageUrl = imageUrl;
      notifyListeners();
    }
  }

  Future<void> deleteProfileImage() async {
    if (_user != null) {
      final defaultImageUrl = 'https://cdn.pixabay.com/photo/2015/10/05/22/37/blank-profile-picture-973460_960_720.png';
      await _db.collection('userInfo').doc(_user!.uid).update({
        'profileImageUrl': defaultImageUrl,
      });
      final storageRef = _storage.ref().child('profile_images').child('${_user!.uid}.jpg');
      await storageRef.delete();
      _profileImageUrl = defaultImageUrl;
      notifyListeners();
    }
  }

  Future<String> _uploadProfileImage(File image) async {
    final storageRef = _storage.ref().child('profile_images').child('${_user!.uid}.jpg');
    await storageRef.putFile(image);
    return await storageRef.getDownloadURL();
  }

  Future<UserCredential?> signUp(String userEmail, String userPassword, String username) async {
    try {
      _isSigning = true;
      _status = Status.authenticating;
      notifyListeners();
      
      // Create user with email and password
      UserCredential wanted = await _auth.createUserWithEmailAndPassword(
        email: userEmail,
        password: userPassword,
      );
      
      // Await the creation of the user document in Firestore
      await createUserDoc(wanted.user!.uid, userEmail, username);
      
      return wanted;
    } catch (e) {
      print(e);
      _status = Status.unauthenticated;
      _isSigning = false;
      notifyListeners();
      return null;
    } finally {
      _isSigning = false;
      if (_status == Status.authenticated) print(true);
    }
  }

  Future<void> createUserDoc(String uid, String email, String username) async {
    try {
      await _db.collection('userInfo').doc(uid).set({
        'mail': email,
        'About Me': 'This is my bio',
        'username': username,
        'profileImageUrl': 'https://cdn.pixabay.com/photo/2015/10/05/22/37/blank-profile-picture-973460_960_720.png',
        'My Routes': [],
        'Total Distance': 0.0,
        'Calories Burned': 0.0,
        'Steps Taken': 0,
        'Lives in': '',
      });
    } catch (e) {
      print('Failed to create user document: $e');
      rethrow; // Optionally rethrow the error to handle it further up the call stack
    }
  }

  Future<bool> logInUser(String userEmail, String userPassword) async {
    _isLoading = true;
    _status = Status.authenticating;
    notifyListeners();

    bool isLoginSuccessful = await tryLogin(userEmail, userPassword);

    if (isLoginSuccessful) {
      _isLoggedIn = true;
      _status = Status.authenticated;
    } else {
      _status = Status.unauthenticated;
    }

    notifyListeners();
    _isLoading = false;

    return isLoginSuccessful;
  }

  Future<bool> tryLogin(String userEmail, String userPassword) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: userEmail,
        password: userPassword,
      );
      return true;
    } catch (error) {
      print(error);
      return false;
    }
  }

  Future<void> _clearUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('userEmail');
    await prefs.remove('userPassword');
  }

  Future<void> signOutUser() async {
    await _auth.signOut();
    _status = Status.unauthenticated;
    _user = null;
    _isLoggedIn = false;
    notifyListeners();
    
    // Clear user data from SharedPreferences
    await _clearUserData();

    return Future.delayed(Duration.zero);
  }

  Future<void> deleteAccount() async {
  try {
    if (_user != null) {
      // Delete user data from Firestore
      await _db.collection('userInfo').doc(_user!.uid).delete();

      // Check if the profile image exists in Storage
      final storageRef = _storage.ref().child('profile_images').child('${_user!.uid}.jpg');
      try {
        await storageRef.getDownloadURL(); // Check if the file exists by attempting to get its URL
        await storageRef.delete(); // If the URL retrieval is successful, delete the file
      } catch (e) {
        if (e is FirebaseException && e.code != 'object-not-found') {
          // If the error is not 'object-not-found', rethrow the error
          rethrow;
        }
        // If the error is 'object-not-found', continue without deleting
      }

      // Delete user account
      await _user!.delete();
      _user = null;
      _status = Status.unauthenticated;
      _isLoggedIn = false;
      notifyListeners();
    }
  } catch (e) {
    print('Failed to delete account: $e');
    rethrow;
  }
}


  Future<void> refreshUserData() async {
    await _fetchUserData();
  }

  Future<void> createEvent(Event event) async {
    if (_user != null) {
      await FirebaseFirestore.instance.collection('events').add(event.toMap());
    }
  }

  Future<List<Event>> getEvents({bool filterByUser = false}) async {
  try {
    if (_user != null) {
      QuerySnapshot snapshot;
      if (filterByUser) {
        snapshot = await FirebaseFirestore.instance.collection('events')
          .where('creatorEmail', isEqualTo: _user!.email).get();
      } else {
        snapshot = await FirebaseFirestore.instance.collection('events').get();
      }

      return snapshot.docs.map((doc) => Event.fromMap(doc.data() as Map<String, dynamic>)).toList();
    }
  } catch (e) {
    print('Error fetching events: $e');
  }
  return [];
}
Future<void> deleteEvent(String eventId) async {
    try {
      await FirebaseFirestore.instance.collection('events').doc(eventId).delete();
      
      // if (_user != null) {
      //   await FirebaseFirestore.instance
      //       .collection('userInfo')
      //       .doc(_user!.uid)
      //       .collection('My Events')
      //       .doc(eventId)
      //       .delete();
      // }
    } catch (e) {
      print('Error deleting event: $e');
    }
  }

  Future<Map<String, double>> fetchGlobalStatistics() async {
  double totalDistance = 0.0;
  double totalCalories = 0.0;
  int totalSteps = 0;

  QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('userInfo').get();
  for (var doc in snapshot.docs) {
  totalDistance += (doc['Total Distance'] ?? 0.0).toDouble();
  totalCalories += (doc['Calories Burned'] ?? 0.0).toDouble();
  
  // Safely cast 'Steps Taken' to int if it's a number, otherwise use 0
  final steps = (doc['Steps Taken'] ?? 0) as num;
  totalSteps += steps.toInt();
  }



  return {
    'totalDistance': totalDistance,
    'totalCalories': totalCalories,
    'totalSteps': totalSteps.toDouble(),
  };
}

Future<List<Map<String, dynamic>>> fetchTopUsers() async {
  List<Map<String, dynamic>> topUsers = [];

  QuerySnapshot snapshot = await FirebaseFirestore.instance
      .collection('userInfo')
      .orderBy('Total Distance', descending: true)
      .limit(3)
      .get();

  for (var doc in snapshot.docs) {
    topUsers.add({
      'username': doc['username'],
      'profileImageUrl': doc['profileImageUrl'] ?? 'https://via.placeholder.com/150',
      'totalDistance': (doc['Total Distance'] ?? 0.0).toDouble(),
      'totalCalories': (doc['Calories Burned'] ?? 0.0).toDouble(),
      'totalSteps': (doc['Steps Taken'] ?? 0),
    });
  }

  return topUsers;
}




}
