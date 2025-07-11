import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'main.dart';
import 'dart:ui';
import 'UserStatus_Firebase.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedIndex = 3;
  late StreamSubscription<List<ConnectivityResult>> _subscription; // Subscription for connectivity changes
  bool _isDialogShowing = false; // Flag to track if the dialog is showing

  @override
  void initState() {
    super.initState();
    _listenToConnectivity(); // Start listening to connectivity changes
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      ConnectivityResult result = results.last;
      if (result == ConnectivityResult.none) {
        _showNoConnectionDialog();
      } else {
        _hideNoConnectionDialog();
      }
    });
  }

  void _showNoConnectionDialog() {
    if (!_isDialogShowing) {
      _isDialogShowing = true;
      Future.delayed(Duration.zero, () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Connection Lost"),
              content: Text("Check your connection"),
            );
          },
        );
      });
    }
  }

  void _hideNoConnectionDialog() {
    if (_isDialogShowing) {
      _isDialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop('dialog');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel(); // Cancel the subscription when the widget is disposed
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/discover');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/community');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }
  
  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Settings'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.password),
                  title: Text('Change Password'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ChangePasswordScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever),
                  title: Text('Delete Account'),
                  onTap: () async {
                    Navigator.of(context).pop(); // Close the dialog
                    await _confirmDeleteAccount();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final userState = Provider.of<UserState>(context, listen: false);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Deletion'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to delete your account?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('No'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Yes'),
              onPressed: () async {
                await userState.deleteAccount();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account deleted successfully')),
                );
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => MyMainScreen()),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProfileImage() async {
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.deleteProfileImage();
    setState(() {});
  }

  void _showProfilePictureDialog(String imageUrl) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop(); // Close the dialog when tapped
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 150,
                  backgroundImage: NetworkImage(imageUrl),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    final userState = Provider.of<UserState>(context);

    // Ensure the fields exist with default values if they are missing
    final totalDistance = userState.totalDistance.toStringAsFixed(2);
    final stepsTaken = userState.stepsTaken ?? 0;
    final caloriesBurned = userState.caloriesBurned ?? 0.0;

    return WillPopScope(
      onWillPop: () async {
        return Future.value(false); // Disable back button
      },
      child: Scaffold(
        backgroundColor: Color(0xFFdbe4ee),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Color(0xFF4c6185),
          title: const Text('RunElite'),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.settings),
              onPressed: _showSettingsDialog,
            ),
            IconButton(
              icon: Icon(Icons.exit_to_app),
              onPressed: () async {
               // Cancel Firestore event listeners before signing out
              await context.read<UserState>().cancelEventListener();

              // Cancel other subscriptions
              _subscription?.cancel();

              // Sign out the user
              await context.read<UserState>().signOutUser();

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Successfully logged out')),
              );

              // Navigate to the main screen and remove all previous routes
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MyMainScreen()),
                (Route<dynamic> route) => false, // Removes all routes except for MyMainScreen
              );
            },
            ),

          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      spreadRadius: 5,
                      blurRadius: 7,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: () => _showProfilePictureDialog(userState.profileImageUrl),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          spreadRadius: 5,
                          blurRadius: 7,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 80,
                      backgroundImage: userState.profileImageUrl.isNotEmpty
                          ? NetworkImage(userState.profileImageUrl)
                          : NetworkImage('https://via.placeholder.com/150'),
                    ),
                  ),
                ),

              ),
              SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: Colors.white, // Background color
                  borderRadius: BorderRadius.circular(10.0), // Rounded corners, optional
                  border: Border.all(
                    color: Colors.grey,
                    width: 1,
                  ),
                ),
                child: Text(
                  userState.username,
                  style: TextStyle(
                    fontSize: 18,
                    shadows: [
                      Shadow(
                        offset: Offset(1.0, 1.0),
                        blurRadius: 3.0,
                        color: Colors.black.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),
              ),
              //SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    'About Me: ',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: TextFormField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: '',
                    labelStyle: TextStyle(color: Colors.black, fontSize: 16),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4c6185)),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4c6185)),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(color: Colors.black, fontSize: 16),
                  controller: TextEditingController(
                    text: userState.aboutMe,
                  ),
                  readOnly: true,
                  maxLines: 4,
                ),
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround, // Distribute the columns evenly
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align content to the start
                    children: [
                      Text(
                        'Lives in:',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 5),
                      Container(
                        width: MediaQuery.of(context).size.width * 0.4, // Adjust width based on screen size
                        child: TextFormField(
                          controller: TextEditingController(text: userState.livesIn),
                          decoration: InputDecoration(
                            labelText: '',
                            labelStyle: TextStyle(color: Colors.black, fontSize: 16),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            suffixIcon: Icon(Icons.location_on),
                          ),
                          cursorColor: Colors.black,
                          maxLines: 1,
                          readOnly: true,
                          style: TextStyle(color: Colors.black, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align content to the start
                    children: [
                      Text(
                        'Total Distance Walked:',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 5),
                      Container(
                        width: MediaQuery.of(context).size.width * 0.4, // Adjust width based on screen size
                        child: TextFormField(
                          controller: TextEditingController(text: '$totalDistance'),
                          decoration: InputDecoration(
                            labelText: '',
                            labelStyle: TextStyle(color: Colors.black, fontSize: 16),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            suffixText: 'km',
                          ),
                          cursorColor: Colors.black,
                          maxLines: 1,
                          readOnly: true,
                          style: TextStyle(color: Colors.black, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround, // Distribute the columns evenly
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align content to the start
                    children: [
                      Text(
                        'Steps Taken:',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 5),
                      Container(
                        width: MediaQuery.of(context).size.width * 0.4, // Adjust width based on screen size
                        child: TextFormField(
                          controller: TextEditingController(text: '$stepsTaken'),
                          decoration: InputDecoration(
                            labelText: '',
                            labelStyle: TextStyle(color: Colors.black, fontSize: 16),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          cursorColor: Colors.black,
                          maxLines: 1,
                          readOnly: true,
                          style: TextStyle(color: Colors.black, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align content to the start
                    children: [
                      Text(
                        'Calories Burned:',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 5),
                      Container(
                        width: MediaQuery.of(context).size.width * 0.4, // Adjust width based on screen size
                        child: TextFormField(
                          controller: TextEditingController(text: '${caloriesBurned.toStringAsFixed(1)}'),
                          decoration: InputDecoration(
                            labelText: '',
                            suffixText: 'cal',
                            labelStyle: TextStyle(color: Colors.black, fontSize: 16),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4c6185)),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          cursorColor: Colors.black,
                          maxLines: 1,
                          readOnly: true,
                          style: TextStyle(color: Colors.black, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => EditProfileScreen()),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit,
                        color: Colors.blue,
                        size: 18,
                      ),
                      SizedBox(width: 4), // Add a little space between the icon and text
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Color(0xFF4c6185),
          type: BottomNavigationBarType.fixed, // Ensures fixed style
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_outline),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_run),
              label: 'Discover',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups), 
              label: 'Community'
              ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: 'Profile',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Color.fromARGB(255, 0, 132, 241),
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _aboutMeController;
  late TextEditingController _livesInController;
  File? _profileImage;
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final userState = Provider.of<UserState>(context, listen: false);
    _usernameController = TextEditingController(text: userState.username);
    _aboutMeController = TextEditingController(text: userState.aboutMe);
    _livesInController = TextEditingController(text: userState.livesIn);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _aboutMeController.dispose();
    _livesInController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    var status = await Permission.photos.status;
    if (status.isDenied || status.isRestricted) {
      status = await Permission.photos.request();
    }
    if (!status.isGranted) {
      print('Gallery permission not granted.');
    }
    var status2 = await Permission.storage.status;
    if (status2.isDenied || status2.isRestricted) {
      status = await Permission.storage.request();
    }
    if (!status2.isGranted) {
      print('Storage permission not granted.');
    }
  }

  Future<void> _pickImage() async {
    await _requestPermissions();
    if (await Permission.photos.isGranted || await Permission.storage.isGranted) {
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
      } else {
        print('No image selected.');
      }
    } else {
      print('Gallery permission not granted.');
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      final userState = Provider.of<UserState>(context, listen: false);
      await userState.updateProfile(
        _usernameController.text,
        _aboutMeController.text,
        _livesInController.text,
        _profileImage,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile Updated Successfully')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _deleteProfileImage() async {
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.deleteProfileImage();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final userState = Provider.of<UserState>(context);
    return Scaffold(
      backgroundColor: Color(0xFFdbe4ee),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Color(0xFF4c6185),
        title: const Text('Edit Profile'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () async {
  // Cancel Firestore event listeners before signing out
  await context.read<UserState>().cancelEventListener();

  // Cancel other subscriptions
  // _subscription?.cancel();

  // Sign out the user
  await context.read<UserState>().signOutUser();

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Successfully logged out')),
  );

  // Navigate to the main screen and remove all previous routes
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => MyMainScreen()),
    (Route<dynamic> route) => false, // Removes all routes except for MyMainScreen
  );
},
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 30),
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              spreadRadius: 5,
                              blurRadius: 7,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 80,
                          backgroundImage: _profileImage != null
                              ? FileImage(_profileImage!)
                              : (userState.profileImageUrl.isNotEmpty
                                  ? NetworkImage(userState.profileImageUrl)
                                  : NetworkImage('https://via.placeholder.com/150')) as ImageProvider,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: IconButton(
                          icon: Icon(Icons.add_a_photo),
                          onPressed: _pickImage,
                          color: Colors.blue,
                          iconSize: 30,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 5),
                  TextButton(
                    onPressed: _deleteProfileImage,
                    child: Text(
                      'Delete Profile Image',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username: ',
                        labelStyle: TextStyle(color: Colors.black, fontSize: 18),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4c6185)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4c6185)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      cursorColor: Colors.black,
                      maxLines: 1,
                      style: TextStyle(color: Colors.black, fontSize: 18),
                      validator: (value) {
                        if (value != null && value.length > 20) {
                          return 'Username too long';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextFormField(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        labelText: 'About Me: ',
                        labelStyle: TextStyle(color: Colors.black, fontSize: 18),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4c6185)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4c6185)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: TextStyle(color: Colors.black, fontSize: 18),
                      controller: _aboutMeController,
                      maxLines: 4,
                    ),
                  ),
                  SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextFormField(
                      controller: _livesInController,
                      decoration: InputDecoration(
                        labelText: 'Lives in:',
                        labelStyle: TextStyle(color: Colors.black, fontSize: 18),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4c6185)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4c6185)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: Icon(Icons.location_on),
                      ),
                      cursorColor: Colors.black,
                      maxLines: 1,
                      style: TextStyle(color: Colors.black, fontSize: 18),
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : () async {
                      await _saveProfile();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4c6185),
                      padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 10),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  @override
  _ChangePasswordScreenState createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscureTextOldPassword = true;
  bool _obscureTextNewPassword = true;
  bool _obscureTextConfirmPassword = true;

  Future<void> _changePassword() async {
    final user = _auth.currentUser;
    if (user != null &&
        _oldPasswordController.text.isNotEmpty &&
        _newPasswordController.text.isNotEmpty &&
        _confirmPasswordController.text.isNotEmpty) {
      if (_newPasswordController.text != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Passwords do not match'),
        ));
        return;
      }
      try {
        // Re-authenticate the user
        UserCredential userCredential = await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: user.email!,
            password: _oldPasswordController.text,
          ),
        );

        // Change the password
        await user.updatePassword(_newPasswordController.text);

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Password changed successfully'),
        ));

        // Pop back to the ProfileScreen
        Navigator.popUntil(context, ModalRoute.withName('/profile'));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to change password: check if old Password is correct'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFdbe4ee),
      appBar: AppBar(
        title: Text('Change Password'),
        backgroundColor: Color(0xFF4c6185),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _oldPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Old Password',
                    fillColor: Colors.white,
                    filled: true,
                    prefixIcon: Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureTextOldPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureTextOldPassword = !_obscureTextOldPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  obscureText: _obscureTextOldPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your old password';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    fillColor: Colors.white,
                    filled: true,
                    prefixIcon: Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureTextNewPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureTextNewPassword = !_obscureTextNewPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  obscureText: _obscureTextNewPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a new password';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    fillColor: Colors.white,
                    filled: true,
                    prefixIcon: Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureTextConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureTextConfirmPassword = !_obscureTextConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  obscureText: _obscureTextConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your new password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _changePassword();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4c6185),
                    padding: EdgeInsets.symmetric(horizontal: 70, vertical: 15),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                  child: Text('Change Password', style: TextStyle(color: Colors.white, fontFamily: 'Oswald',)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
