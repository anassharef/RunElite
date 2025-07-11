import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'community.dart';
import 'HomeScreen.dart';
import 'DiscoverScreen.dart';
import 'ProfileScreen.dart';
import 'UserStatus_Firebase.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Initialize FlutterLocalNotificationsPlugin
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('icon');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Trigger notification
    flutterLocalNotificationsPlugin.show(
      0,
      'Event Reminder',
      inputData!['message'],
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'your_channel_id',
          'Event Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedEmail = prefs.getString('userEmail');
  String? savedPassword = prefs.getString('userPassword');

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('icon');
  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  runApp(App(savedEmail: savedEmail, savedPassword: savedPassword));
}

class App extends StatelessWidget {
  final String? savedEmail;
  final String? savedPassword;

  App({required this.savedEmail, required this.savedPassword});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => UserState(),
      child: MaterialApp(
        title: 'RunElite',
        theme: ThemeData(
          primarySwatch: Colors.blueGrey,
          colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blueGrey),
          snackBarTheme: SnackBarThemeData(
            dismissDirection: DismissDirection.horizontal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: Color.fromARGB(200, 11, 11, 11),
            contentTextStyle: TextStyle(color: Color(0xFFdbe4ee)),
          ),
          fontFamily: 'Oswald',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF4c6185),
            foregroundColor: Color(0xFFdbe4ee),
          ),
          bottomAppBarTheme: const BottomAppBarTheme(
            color: Color(0xFF4c6185),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF4c6185),
            selectedItemColor: Color.fromARGB(255, 0, 119, 255),
            unselectedItemColor: Color.fromARGB(255, 255, 255, 255).withOpacity(0.5),
          ),
        ),
        home: savedEmail != null && savedPassword != null
            ? AutoLoginScreen(savedEmail: savedEmail!, savedPassword: savedPassword!)
            : MyMainScreen(),
        routes: {
          '/home': (context) => HomeScreen(),
          '/discover': (context) => DiscoverScreen(),
          '/profile': (context) => ProfileScreen(),
          '/edit_profile': (context) => EditProfileScreen(),
          '/change_password': (context) => ChangePasswordScreen(),
          '/community': (context) => CommunityScreen(),
        },
      ),
    );
  }
}

class MyMainScreen extends StatefulWidget {
  MyMainScreen({Key? key}) : super(key: key);

  @override
  _MyMainScreenState createState() => _MyMainScreenState();
}

class _MyMainScreenState extends State<MyMainScreen> {
  final TextEditingController emailCtrl = TextEditingController();
  late final TextEditingController pwdCtrl;
  bool rememberMe = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final errorLoginSnackBar = SnackBar(
    content: Text('There was an error logging into the app'),
  );

  final errorSignUpSnackBar = SnackBar(
    content: Text('There was an error signing up into the app'),
  );

  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    pwdCtrl = TextEditingController();
    _loadUserEmail();
    _listenToConnectivity();
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

  void _loadUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedEmail = prefs.getString('userEmail');
    String? savedPassword = prefs.getString('userPassword');
    if (savedEmail != null && savedPassword != null) {
      setState(() {
        emailCtrl.text = savedEmail;
        pwdCtrl.text = savedPassword;
        rememberMe = true;
      });
    }
  }

  void _saveUserData(String email, String password) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString('userEmail', email);
      await prefs.setString('userPassword', password);
    } else {
      await prefs.remove('userEmail');
      await prefs.remove('userPassword');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    emailCtrl.dispose();
    pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFdbe4ee),
      appBar: AppBar(
        backgroundColor: Color(0xFF4c6185),
        automaticallyImplyLeading: false,
        title: const Text('RunElite'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/background.jpeg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 60),
                        SizedBox(
                          width: 160,
                          height: 180,
                          child: Title(
                            color: const Color(0xFF4c6185),
                            child: const Text(
                              'RunElite',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                                color: Color.fromARGB(166, 255, 255, 255),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 60),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                              controller: emailCtrl,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email),
                                fillColor: Colors.white,
                                filled: true,
                                labelStyle: TextStyle(color: Colors.black),
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                              ),
                              cursorColor: Colors.black,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email';
                                }
                                return null;
                              },
                            ),
                              const SizedBox(height: 10),
                              PasswordField_sign(
                                controller: pwdCtrl,
                                labelText: 'Password',
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.scale(
                              scale: 1.3,
                              child: Checkbox(
                                value: rememberMe,
                                onChanged: (bool? value) {
                                  setState(() {
                                    rememberMe = value ?? false;
                                  });
                                },
                                activeColor: Color(0xFF4c6185),
                                checkColor: Color.fromARGB(255, 255, 255, 255),
                                side: MaterialStateBorderSide.resolveWith(
                                  (states) => BorderSide(
                                    width: 2.0,
                                    color: Color.fromARGB(255, 255, 255, 255),
                                  ),
                                ),
                              ),
                            ),
                            const Text(
                              "Remember Me",
                              style: TextStyle(
                                fontSize: 18,
                                color: Color.fromARGB(231, 255, 255, 255),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: context.watch<UserState>().isLoading
                              ? null
                              : () async {
                                  if (_formKey.currentState!.validate()) {
                                    bool loginSuccess = await context
                                        .read<UserState>()
                                        .logInUser(emailCtrl.text, pwdCtrl.text);
                                    if (!context.mounted) return;
                                    if (loginSuccess) {
                                      _saveUserData(emailCtrl.text, pwdCtrl.text);
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(builder: (context) => HomeScreen()),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(errorLoginSnackBar);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4c6185),
                            padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 10),
                          ),
                          child: context.watch<UserState>().isLoading
                              ? const CircularProgressIndicator()
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Text(
                                      'Log In',
                                      style: TextStyle(color: Color.fromARGB(255, 255, 255, 255), fontSize: 16),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.login, color: Color.fromARGB(255, 255, 255, 255)),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            Expanded(child: Divider(color: Color.fromARGB(166, 255, 255, 255))),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text("or", style: TextStyle(color: Color.fromARGB(166, 255, 255, 255))),
                            ),
                            Expanded(child: Divider(color: Color.fromARGB(166, 255, 255, 255))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color.fromARGB(255, 255, 255, 255),
                            padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 10),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => SignUp()),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Sign Up',
                                style: TextStyle(color: Color.fromARGB(255, 0, 0, 0), fontSize: 16),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.person_add, color: Color.fromARGB(255, 0, 0, 0)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SignUp extends StatefulWidget {
  const SignUp({Key? key}) : super(key: key);

  @override
  State<SignUp> createState() => _SignUpScreen();
}

class _SignUpScreen extends State<SignUp> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController pwdCtrl = TextEditingController();
  final TextEditingController confirmPwdCtrl = TextEditingController();
  final TextEditingController usernameCtrl = TextEditingController();

  SnackBar errorSignUpSnackBar = const SnackBar(
    content: Text('Sign up failed'),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFdbe4ee),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4c6185),
        title: const Text('Create Account'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/background.jpeg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        "Welcome to RunElite!",
                        style: TextStyle(
                          fontSize: 40,
                          fontFamily: 'Oswald',
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: Color.fromARGB(166, 255, 255, 255),
                        ),
                      ),
                      const SizedBox(height: 80),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Create a new Account:",
                          style: TextStyle(
                            fontFamily: 'Oswald',
                            fontSize: 20,
                            color: Color.fromARGB(166, 255, 255, 255),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email),
                          fillColor: Colors.white,
                          filled: true,
                          labelStyle: const TextStyle(color: Colors.black),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          
                        ),
                        cursorColor: Colors.black,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: usernameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(Icons.person),
                          fillColor: Colors.white,
                          filled: true,
                          labelStyle: const TextStyle(color: Colors.black),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                        cursorColor: Colors.black,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your username';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      PasswordField_sign(
                        controller: pwdCtrl,
                        labelText: 'Password',
                      ),
                      const SizedBox(height: 10),
                      PasswordField_sign(
                        controller: confirmPwdCtrl,
                        labelText: 'Confirm Password',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != pwdCtrl.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4c6185),
                          padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 10),
                        ),
                        onPressed: () async {
                          if (_formKey.currentState?.validate() ?? false) {
                            if (Provider.of<UserState>(context, listen: false).isSigning) {
                              return;
                            }

                            try {
                              var isSuccess = await context.read<UserState>().signUp(
                                emailCtrl.text,
                                pwdCtrl.text,
                                usernameCtrl.text,
                              );

                              if (isSuccess != null) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => HomeScreen()),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(errorSignUpSnackBar);
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(errorSignUpSnackBar);
                            }
                          }
                        },
                        child: context.watch<UserState>().isSigning
                            ? const CircularProgressIndicator()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text(
                                    'Sign Up',
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.person_add, color: Colors.white),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PasswordField_sign extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final FormFieldValidator<String>? validator;

  const PasswordField_sign({
    Key? key,
    required this.controller,
    required this.labelText,
    this.validator,
  }) : super(key: key);

  @override
  _PasswordFieldState_sign createState() => _PasswordFieldState_sign();
}

class _PasswordFieldState_sign extends State<PasswordField_sign> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscureText,
      decoration: InputDecoration(
        labelText: widget.labelText,
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
        ),
        fillColor: Colors.white,
        filled: true,
        labelStyle: const TextStyle(color: Colors.black),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
      ),
      cursorColor: Colors.black,
      validator: widget.validator,
    );
  }
}

class PasswordField extends StatefulWidget {
  final Function(TextEditingController) onControllerCreated;

  PasswordField({Key? key, required this.onControllerCreated});

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;
  late final TextEditingController pwdCtrl;

  @override
  void initState() {
    super.initState();
    pwdCtrl = TextEditingController();
    widget.onControllerCreated(pwdCtrl);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 400,
        child: TextField(
          controller: pwdCtrl,
          obscureText: _obscureText,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock),
            fillColor: Colors.white,
            filled: true,
            labelStyle: TextStyle(color: Colors.black),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20.0),
              borderSide: BorderSide(color: Color(0xFF4c6185)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20.0),
              borderSide: BorderSide(color: Color(0xFF4c6185)),
            ),
            suffixIcon: IconButton(
              icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            ),
          ),
          cursorColor: Colors.black,
        ),
      ),
    );
  }
}

class ConfirmPasswordField extends StatefulWidget {
  final Function(TextEditingController) onControllerCreated;

  ConfirmPasswordField({Key? key, required this.onControllerCreated}) : super(key: key);

  @override
  _ConfirmPasswordFieldState createState() => _ConfirmPasswordFieldState();
}

class _ConfirmPasswordFieldState extends State<ConfirmPasswordField> {
  bool _obscureText = true;
  late final TextEditingController confirmPwdCtrl;

  @override
  void initState() {
    super.initState();
    confirmPwdCtrl = TextEditingController();
    widget.onControllerCreated(confirmPwdCtrl);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 400,
        child: TextField(
          controller: confirmPwdCtrl,
          obscureText: _obscureText,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.lock),
            fillColor: Colors.white,
            filled: true,
            labelStyle: TextStyle(color: Colors.black),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20.0),
              borderSide: BorderSide(color: Color(0xFF4c6185)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20.0),
              borderSide: BorderSide(color: Color(0xFF4c6185)),
            ),
            suffixIcon: IconButton(
              icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            ),
          ),
          cursorColor: Colors.black,
        ),
      ),
    );
  }
}

class AutoLoginScreen extends StatelessWidget {
  final String savedEmail;
  final String savedPassword;

  AutoLoginScreen({required this.savedEmail, required this.savedPassword});

  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isDialogShowing = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance?.addPostFrameCallback((_) async {
      bool loginSuccess = await context.read<UserState>().logInUser(savedEmail, savedPassword);
      if (loginSuccess) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MyMainScreen()),
        );
      }
    });

    return Scaffold(
      backgroundColor: Color(0xFFdbe4ee),
      appBar: AppBar(
        backgroundColor: Color(0xFF4c6185),
        automaticallyImplyLeading: false,
        title: const Text('RunElite'),
        centerTitle: true,
      ),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
