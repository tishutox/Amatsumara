import 'dart:async';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:remixicon/remixicon.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _isSubmitting = false;
  bool _isUploadingAvatar = false;
  Uint8List? _registrationAvatarBytes;
  String? _registrationAvatarExtension;
  late final StreamSubscription<AuthState> _authSubscription;

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
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _handleAuthState,
    );
  }

  void _handleAuthState(AuthState state) {
    if (!mounted) {
      return;
    }
    setState(() {});

    final session = state.session;
    if (state.event == AuthChangeEvent.signedIn &&
        session != null &&
        _registrationAvatarBytes != null &&
        !_isUploadingAvatar) {
      unawaited(_uploadPendingRegistrationAvatar(session.user));
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final auth = Supabase.instance.client.auth;

    try {
      if (_mode == _AuthMode.signUp) {
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'first_name': _firstNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            'display_name': _displayNameController.text.trim(),
            'username': _usernameController.text.trim(),
            'birthday': _birthday!.toIso8601String().split('T').first,
            'country': _country,
          },
        );
        if (!mounted) {
          return;
        }
        final needsConfirmation = response.session == null;
        if (response.session != null &&
            _registrationAvatarBytes != null &&
            !_isUploadingAvatar) {
          await _uploadPendingRegistrationAvatar(response.session!.user);
        }
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              needsConfirmation
                  ? 'Account created. Check your email to confirm it.'
                  : 'Your account has been created.',
            ),
          ),
        );
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _isUploadingAvatar) {
      return;
    }

    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null || !mounted) {
      return;
    }

    setState(() => _isUploadingAvatar = true);
    try {
      final avatar = await _readAvatar(image);
      await _uploadAvatar(
        user: user,
        bytes: avatar.bytes,
        extension: avatar.extension,
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile image saved.')));
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on StorageException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The profile image could not be saved.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _pickRegistrationAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null || !mounted) {
      return;
    }

    try {
      final avatar = await _readAvatar(image);
      setState(() {
        _registrationAvatarBytes = avatar.bytes;
        _registrationAvatarExtension = avatar.extension;
      });
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _uploadPendingRegistrationAvatar(User user) async {
    final bytes = _registrationAvatarBytes;
    final extension = _registrationAvatarExtension;
    if (bytes == null || extension == null || _isUploadingAvatar) {
      return;
    }

    setState(() => _isUploadingAvatar = true);
    try {
      await _uploadAvatar(user: user, bytes: bytes, extension: extension);
      if (mounted) {
        setState(() {
          _registrationAvatarBytes = null;
          _registrationAvatarExtension = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account and profile image saved.')),
        );
      }
    } on StorageException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account created, but image failed: ${error.message}',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created, but the image could not be saved.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return _SignedInProfile(
        user: user,
        isUploadingAvatar: _isUploadingAvatar,
        onChangeAvatar: _pickAndUploadAvatar,
        onSignOut: _signOut,
      );
    }

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
                          imageBytes: _registrationAvatarBytes,
                          onPressed: _pickRegistrationAvatar,
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
                        if (isSignUp)
                          _AuthTextField(
                            controller: _usernameController,
                            label: 'Username',
                            icon: Remix.account_circle_line,
                            maxLength: 20,
                            validator: _usernameValidator,
                          )
                        else
                          _AuthTextField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Remix.mail_line,
                            keyboardType: TextInputType.emailAddress,
                            validator: _emailValidator,
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
                      onPressed: _isSubmitting ? null : _submit,
                      icon: Icon(
                        _isSubmitting
                            ? Icons.hourglass_top_rounded
                            : isSignUp
                            ? Icons.person_add_alt_1_outlined
                            : Icons.login_outlined,
                      ),
                      label: Text(
                        _isSubmitting
                            ? 'Please wait...'
                            : isSignUp
                            ? 'Create account'
                            : 'Sign in',
                      ),
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

class _SignedInProfile extends StatelessWidget {
  const _SignedInProfile({
    required this.user,
    required this.isUploadingAvatar,
    required this.onChangeAvatar,
    required this.onSignOut,
  });

  final User user;
  final bool isUploadingAvatar;
  final Future<void> Function() onChangeAvatar;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName = metadata['display_name'] as String?;
    final username = metadata['username'] as String?;
    final avatarUrl = metadata['avatar_url'] as String?;

    return ListView(
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CircularProfileImage(
                    size: 84,
                    imageProvider: avatarUrl == null
                        ? null
                        : NetworkImage(avatarUrl),
                    fallback: Text(
                      (displayName ?? user.email ?? '?')[0].toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    child: OutlinedButton.icon(
                      onPressed: isUploadingAvatar ? null : onChangeAvatar,
                      icon: Icon(
                        isUploadingAvatar
                            ? Icons.hourglass_top_rounded
                            : Remix.camera_line,
                      ),
                      label: Text(
                        isUploadingAvatar
                            ? 'Uploading...'
                            : avatarUrl == null
                            ? 'Add profile image'
                            : 'Change profile image',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName ?? 'Lumii Quest member',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (username != null) ...[
                    const SizedBox(height: 4),
                    Text('@$username', textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 4),
                  Text(user.email ?? '', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<({Uint8List bytes, String extension})> _readAvatar(XFile image) async {
  final bytes = await image.readAsBytes();
  if (bytes.lengthInBytes > 5 * 1024 * 1024) {
    throw const FormatException('The image must be smaller than 5 MB.');
  }
  return (bytes: bytes, extension: _imageExtension(image.name));
}

Future<void> _uploadAvatar({
  required User user,
  required Uint8List bytes,
  required String extension,
}) async {
  final path = '${user.id}/avatar.$extension';
  final storage = Supabase.instance.client.storage.from('avatars');
  await storage.uploadBinary(
    path,
    bytes,
    fileOptions: FileOptions(
      upsert: true,
      contentType: _imageContentType(extension),
      cacheControl: '3600',
    ),
  );

  final publicUrl = storage.getPublicUrl(path);
  final avatarUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  await Supabase.instance.client.auth.updateUser(
    UserAttributes(data: {'avatar_url': avatarUrl}),
  );
}

String _imageExtension(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    _ => throw const FormatException('Choose a JPG, PNG or WebP image.'),
  };
}

String _imageContentType(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

String _friendlyAuthError(Object error) {
  final message = error.toString();
  final normalized = message.toLowerCase();
  if (normalized.contains('failed host lookup') ||
      normalized.contains('socketexception')) {
    return 'Supabase could not be reached. Check your internet or DNS connection.';
  }
  return 'Account request failed. Please try again.';
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
  const _ProfileImagePicker({
    required this.imageBytes,
    required this.onPressed,
  });

  final Uint8List? imageBytes;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        _CircularProfileImage(
          size: 80,
          imageProvider: imageBytes == null ? null : MemoryImage(imageBytes!),
          fallback: Icon(Remix.camera_line, color: primary, size: 30),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Remix.camera_line),
          label: Text(
            imageBytes == null
                ? 'Select profile image'
                : 'Change profile image',
          ),
        ),
      ],
    );
  }
}

class _CircularProfileImage extends StatelessWidget {
  const _CircularProfileImage({
    required this.size,
    required this.imageProvider,
    required this.fallback,
  });

  final double size;
  final ImageProvider? imageProvider;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final image = imageProvider;

    return ClipOval(
      child: ColoredBox(
        color: primary.withValues(alpha: 0.14),
        child: SizedBox.square(
          dimension: size,
          child: image == null
              ? Center(child: fallback)
              : Image(
                  image: image,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(child: fallback),
                ),
        ),
      ),
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
  return null;
}
