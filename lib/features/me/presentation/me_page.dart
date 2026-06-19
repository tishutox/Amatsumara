import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remixicon/remixicon.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

enum _AuthMode { signUp, signIn }

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _birthdayController = TextEditingController();

  _AuthMode _mode = _AuthMode.signUp;
  DateTime? _birthday;
  String? _country;

  static const _countries = <String>[
    'Albania',
    'Austria',
    'Germany',
    'Romania',
    'Switzerland',
    'United Kingdom',
    'United States',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      switchToInputEntryModeIcon: const Icon(Remix.pencil_line),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _birthday = selected;
      _birthdayController.text =
          '${selected.day.toString().padLeft(2, '0')}.'
          '${selected.month.toString().padLeft(2, '0')}.'
          '${selected.year}';
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final action = _mode == _AuthMode.signUp ? 'Sign up' : 'Sign in';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action is ready for backend integration.')),
    );
  }

  void _showProfileImageHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile image upload will be connected with storage.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == _AuthMode.signUp;

    return ListView(
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthHeader(
                      mode: _mode,
                      onChanged: (mode) {
                        setState(() => _mode = mode);
                        _formKey.currentState?.reset();
                      },
                    ),
                    const SizedBox(height: 20),
                    if (isSignUp) ...[
                      Center(
                        child: _ProfileImagePicker(
                          onPressed: _showProfileImageHint,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ResponsiveFields(
                        children: [
                          _AuthTextField(
                            controller: _firstNameController,
                            label: 'First name',
                            icon: Remix.profile_line,
                            maxLength: 30,
                            validator: (value) =>
                                _requiredMax(value, 'First name', 30),
                          ),
                          _AuthTextField(
                            controller: _lastNameController,
                            label: 'Last name',
                            icon: Remix.profile_line,
                            maxLength: 30,
                            validator: (value) =>
                                _requiredMax(value, 'Last name', 30),
                          ),
                        ],
                      ),
                      ContentLayout.sectionGap,
                      _ResponsiveFields(
                        children: [
                          _AuthTextField(
                            controller: _displayNameController,
                            label: 'Display name',
                            icon: Remix.user_line,
                            maxLength: 20,
                            validator: (value) =>
                                _requiredMax(value, 'Display name', 20),
                          ),
                          _AuthTextField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Remix.mail_line,
                            keyboardType: TextInputType.emailAddress,
                            validator: _emailValidator,
                          ),
                        ],
                      ),
                      ContentLayout.sectionGap,
                    ],
                    _ResponsiveFields(
                      children: [
                        _AuthTextField(
                          controller: _usernameController,
                          label: 'Username',
                          icon: Remix.account_circle_line,
                          maxLength: 20,
                          validator: _usernameValidator,
                        ),
                        _AuthTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Remix.lock_2_line,
                          obscureText: true,
                          validator: _passwordValidator,
                        ),
                      ],
                    ),
                    if (isSignUp) ...[
                      ContentLayout.sectionGap,
                      _ResponsiveFields(
                        children: [
                          _AuthTextField(
                            controller: _birthdayController,
                            label: 'Birthday',
                            icon: Remix.cake_line,
                            readOnly: true,
                            onTap: _pickBirthday,
                            validator: (value) => _required(value, 'Birthday'),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _country,
                            decoration: _fieldDecoration(
                              label: 'Country',
                              icon: Remix.earth_line,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            items: _countries
                                .map(
                                  (country) => DropdownMenuItem<String>(
                                    value: country,
                                    child: Text(country),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() => _country = value);
                            },
                            validator: (value) =>
                                value == null ? 'Country is required.' : null,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: Icon(
                        isSignUp
                            ? Icons.person_add_alt_1_outlined
                            : Icons.login_outlined,
                      ),
                      label: Text(isSignUp ? 'Create account' : 'Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          mode == _AuthMode.signUp ? 'Create account' : 'Welcome back',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: primary,
            fontWeight: FontWeight.w800,
          ),
        );
        final modeSwitch = SegmentedButton<_AuthMode>(
          segments: const [
            ButtonSegment<_AuthMode>(
              value: _AuthMode.signUp,
              label: Text('Sign Up'),
              icon: Icon(Icons.person_add_alt_1_outlined),
            ),
            ButtonSegment<_AuthMode>(
              value: _AuthMode.signIn,
              label: Text('Sign In'),
              icon: Icon(Icons.login_outlined),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) => onChanged(value.first),
        );

        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: modeSwitch),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            modeSwitch,
          ],
        );
      },
    );
  }
}

class _ProfileImagePicker extends StatelessWidget {
  const _ProfileImagePicker({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: primary.withValues(alpha: 0.14),
          child: Icon(Remix.camera_line, color: primary, size: 30),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Remix.camera_line),
          label: const Text('Profile image'),
        ),
      ],
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) ContentLayout.sectionGap,
                children[index],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 14),
              Expanded(child: children[index]),
            ],
          ],
        );
      },
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    this.keyboardType,
    this.maxLength,
    this.obscureText = false,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool obscureText;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      onTap: onTap,
      maxLength: maxLength,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      decoration: _fieldDecoration(label: label, icon: icon),
      validator: validator,
    );
  }
}

InputDecoration _fieldDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    counterText: '',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
  );
}

String? _required(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required.';
  }
  return null;
}

String? _requiredMax(String? value, String label, int maxLength) {
  final requiredError = _required(value, label);
  if (requiredError != null) {
    return requiredError;
  }
  if (value!.trim().length > maxLength) {
    return '$label can be up to $maxLength characters.';
  }
  return null;
}

String? _emailValidator(String? value) {
  final requiredError = _required(value, 'Email');
  if (requiredError != null) {
    return requiredError;
  }
  if (!value!.contains('@') || !value.contains('.')) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? _usernameValidator(String? value) {
  final requiredError = _required(value, 'Username');
  if (requiredError != null) {
    return requiredError;
  }
  final username = value!.trim();
  if (username.length > 20) {
    return 'Username can be up to 20 characters.';
  }
  if (!_usernamePattern.hasMatch(username)) {
    return 'Use only A-Z, a-z, 0-9, -, _ and .';
  }
  return null;
}

String? _passwordValidator(String? value) {
  final requiredError = _required(value, 'Password');
  if (requiredError != null) {
    return requiredError;
  }
  final password = value!.trim();
  if (password.length < 8) {
    return 'Password needs at least 8 characters.';
  }
  if (!_usernamePattern.hasMatch(password)) {
    return 'Use only A-Z, a-z, 0-9, -, _ and .';
  }
  return null;
}
