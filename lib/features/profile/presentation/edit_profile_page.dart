import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lumii_quest/features/profile/domain/social_platform.dart';
import 'package:lumii_quest/core/theme/saved_app_theme.dart';
import 'package:remixicon/remixicon.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _repository = ProfileRepository();

  UserProfile? _profile;
  BioAlignment _alignment = BioAlignment.left;
  List<ProfileLink> _links = [];
  List<ProfileMention> _mentions = [];
  Color _backgroundColor = Colors.white;
  Color _accentColor = const Color(0xFF5860C3);
  Uint8List? _avatarBytes;
  String? _avatarExtension;
  Uint8List? _bannerBytes;
  String? _bannerExtension;
  bool _removeAvatar = false;
  bool _removeBanner = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _loadError = 'Sign in to edit your profile.';
      });
      return;
    }

    try {
      final profile = await _repository.getById(user.id);
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loading = false;
          _loadError =
              'Profile data is not set up yet. Run supabase/profiles.sql first.';
        });
        return;
      }
      _displayNameController.text = profile.displayName;
      _bioController.text = profile.bio;
      setState(() {
        _profile = profile;
        _alignment = profile.bioAlignment;
        _links = [...profile.links];
        _mentions = [...profile.mentions];
        _backgroundColor = profile.backgroundColor;
        _accentColor = profile.accentColor;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Profile could not be loaded: $error';
        });
      }
    }
  }

  Future<void> _pickImage({required bool banner}) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: banner ? 1920 : 1024,
      maxHeight: banner ? 800 : 1024,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;

    try {
      final bytes = await image.readAsBytes();
      final limit = banner ? 10 * 1024 * 1024 : 5 * 1024 * 1024;
      if (bytes.lengthInBytes > limit) {
        throw FormatException(
          'The ${banner ? 'banner' : 'image'} is too large.',
        );
      }
      final extension = _imageExtension(image.name);
      setState(() {
        if (banner) {
          _bannerBytes = bytes;
          _bannerExtension = extension;
          _removeBanner = false;
        } else {
          _avatarBytes = bytes;
          _avatarExtension = extension;
          _removeAvatar = false;
        }
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _addSocial() async {
    final result = await showDialog<ProfileLink>(
      context: context,
      builder: (_) => const _SocialDialog(),
    );
    if (result != null && mounted) {
      setState(() => _links = [..._links, result]);
    }
  }

  Future<void> _addMention() async {
    final result = await showDialog<ProfileMention>(
      context: context,
      builder: (_) => const _MentionDialog(),
    );
    if (result != null && mounted) {
      if (_mentions.any(
        (mention) =>
            mention.username.toLowerCase() == result.username.toLowerCase(),
      )) {
        _showMessage('This person is already added.');
        return;
      }
      setState(() => _mentions = [..._mentions, result]);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final user = Supabase.instance.client.auth.currentUser;
    final profile = _profile;
    if (user == null || profile == null) return;

    setState(() => _saving = true);
    try {
      var avatarUrl = profile.avatarUrl;
      var bannerUrl = profile.bannerUrl;

      if (_removeAvatar) {
        await _clearStorageFolder('avatars', user.id);
        avatarUrl = null;
      } else if (_avatarBytes != null && _avatarExtension != null) {
        avatarUrl = await _uploadImage(
          bucket: 'avatars',
          userId: user.id,
          fileName: 'avatar.${_avatarExtension!}',
          bytes: _avatarBytes!,
          extension: _avatarExtension!,
        );
      }

      if (_removeBanner) {
        await _clearStorageFolder('profile-banners', user.id);
        bannerUrl = null;
      } else if (_bannerBytes != null && _bannerExtension != null) {
        bannerUrl = await _uploadImage(
          bucket: 'profile-banners',
          userId: user.id,
          fileName: 'banner.${_bannerExtension!}',
          bytes: _bannerBytes!,
          extension: _bannerExtension!,
        );
      }

      final draft = ProfileDraft(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text,
        bioAlignment: _alignment,
        avatarUrl: avatarUrl,
        bannerUrl: bannerUrl,
        links: _links,
        mentions: _mentions,
        backgroundColor: _backgroundColor,
        accentColor: _accentColor,
      );
      await _repository.save(profile.id, draft);
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {'display_name': draft.displayName, 'avatar_url': avatarUrl},
        ),
      );

      if (mounted) {
        _showMessage('Profile saved.');
        context.pop(true);
      }
    } on ProfileSaveException catch (error) {
      _showMessage(error.message);
    } on StorageException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Profile could not be saved: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SavedAppTheme(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ImageEditor(
                              title: 'Profile image',
                              height: 120,
                              circular: true,
                              imageProvider: _avatarBytes != null
                                  ? MemoryImage(_avatarBytes!)
                                  : !_removeAvatar &&
                                        _profile!.avatarUrl != null
                                  ? NetworkImage(_profile!.avatarUrl!)
                                  : null,
                              onChange: () => _pickImage(banner: false),
                              onRemove: () => setState(() {
                                _avatarBytes = null;
                                _avatarExtension = null;
                                _removeAvatar = true;
                              }),
                            ),
                            const SizedBox(height: 20),
                            _ImageEditor(
                              title: 'Profile banner',
                              aspectRatio: 3,
                              recommendation:
                                  'Recommended size: 1500 × 500 px (3:1)',
                              imageProvider: _bannerBytes != null
                                  ? MemoryImage(_bannerBytes!)
                                  : !_removeBanner &&
                                        _profile!.bannerUrl != null
                                  ? NetworkImage(_profile!.bannerUrl!)
                                  : null,
                              onChange: () => _pickImage(banner: true),
                              onRemove: () => setState(() {
                                _bannerBytes = null;
                                _bannerExtension = null;
                                _removeBanner = true;
                              }),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _displayNameController,
                              maxLength: 50,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Display name is required.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _bioController,
                              minLines: 7,
                              maxLines: 14,
                              maxLength: 5000,
                              textAlign: _alignment.textAlign,
                              decoration: const InputDecoration(
                                labelText: 'Bio',
                                hintText: 'Links: (Text)[https://example.com]',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<BioAlignment>(
                              initialValue: _alignment,
                              decoration: const InputDecoration(
                                labelText: 'Bio alignment',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final value in BioAlignment.values)
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _alignment = value);
                                }
                              },
                            ),
                            const SizedBox(height: 26),
                            Text(
                              'Profile colors',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _ColorPickerField(
                                  label: 'Background',
                                  color: _backgroundColor,
                                  onChanged: (color) =>
                                      setState(() => _backgroundColor = color),
                                ),
                                _ColorPickerField(
                                  label: 'Links & icons',
                                  color: _accentColor,
                                  onChanged: (color) =>
                                      setState(() => _accentColor = color),
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            _EditorSection(
                              title: 'Socials',
                              description:
                                  'Add your username and choose its platform.',
                              onAdd: _addSocial,
                              children: [
                                for (
                                  var index = 0;
                                  index < _links.length;
                                  index++
                                )
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(_links[index].platform.icon),
                                    title: Text(_links[index].label),
                                    subtitle: Text(_links[index].username),
                                    trailing: IconButton(
                                      onPressed: () => setState(
                                        () => _links.removeAt(index),
                                      ),
                                      icon: const Icon(Remix.delete_bin_line),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _EditorSection(
                              title: 'People',
                              description:
                                  'Reference another profile with your own tag (15 characters max).',
                              onAdd: _addMention,
                              children: [
                                for (
                                  var index = 0;
                                  index < _mentions.length;
                                  index++
                                )
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Remix.user_heart_line),
                                    title: Text(_mentions[index].tag),
                                    subtitle: Text(
                                      '@${_mentions[index].username}',
                                    ),
                                    trailing: IconButton(
                                      onPressed: () => setState(
                                        () => _mentions.removeAt(index),
                                      ),
                                      icon: const Icon(Remix.delete_bin_line),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: const Icon(Remix.save_line),
                              label: Text(_saving ? 'Saving…' : 'Save profile'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ImageEditor extends StatelessWidget {
  const _ImageEditor({
    required this.title,
    required this.imageProvider,
    required this.onChange,
    required this.onRemove,
    this.height,
    this.aspectRatio,
    this.recommendation,
    this.circular = false,
  });

  final String title;
  final double? height;
  final double? aspectRatio;
  final String? recommendation;
  final ImageProvider? imageProvider;
  final VoidCallback onChange;
  final VoidCallback onRemove;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final image = SizedBox(
      width: circular ? height : double.infinity,
      height: height,
      child: imageProvider == null
          ? ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              child: const Center(child: Icon(Remix.image_add_line, size: 36)),
            )
          : Image(image: imageProvider!, fit: BoxFit.cover),
    );
    final preview = aspectRatio == null
        ? image
        : AspectRatio(aspectRatio: aspectRatio!, child: image);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (recommendation != null) ...[
          const SizedBox(height: 3),
          Text(recommendation!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 9),
        Align(
          alignment: Alignment.center,
          child: circular
              ? ClipOval(child: preview)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: preview,
                ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onChange,
              icon: const Icon(Remix.image_edit_line),
              label: const Text('Change'),
            ),
            TextButton.icon(
              onPressed: imageProvider == null ? null : onRemove,
              icon: const Icon(Remix.delete_bin_line),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.description,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final String description;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Remix.add_line),
              label: const Text('Add'),
            ),
          ],
        ),
        Text(description),
        ...children,
      ],
    );
  }
}

class _SocialDialog extends StatefulWidget {
  const _SocialDialog();

  @override
  State<_SocialDialog> createState() => _SocialDialogState();
}

class _SocialDialogState extends State<_SocialDialog> {
  final _username = TextEditingController();
  SocialPlatform _platform = SocialPlatform.instagram;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add social'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _username,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SocialPlatform>(
            initialValue: _platform,
            decoration: const InputDecoration(labelText: 'Platform'),
            items: [
              for (final platform in SocialPlatform.selectable)
                DropdownMenuItem(
                  value: platform,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(platform.icon, size: 19),
                      const SizedBox(width: 10),
                      Text(platform.label),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _platform = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: context.pop, child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final username = _username.text.trim();
            if (username.isEmpty) return;
            context.pop(
              ProfileLink(
                platform: _platform,
                username: username,
                url: _platform.profileUrl(username),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ColorPickerField extends StatelessWidget {
  const _ColorPickerField({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final result = await showDialog<Color>(
          context: context,
          builder: (_) => _ColorDialog(initialColor: color),
        );
        if (result != null) onChanged(result);
      },
      icon: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      label: Text('$label  ${profileColorToHex(color)}'),
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  static const _presets = [
    Color(0xFFFFFFFF),
    Color(0xFFF4F2FF),
    Color(0xFFFFF1F5),
    Color(0xFFFFF5E6),
    Color(0xFFEAF8F1),
    Color(0xFFEAF4FF),
    Color(0xFF121212),
    Color(0xFF1E2340),
    Color(0xFF5860C3),
    Color(0xFFDB5DC9),
    Color(0xFFF90142),
    Color(0xFF00A884),
  ];

  late Color _selected = widget.initialColor;
  late final TextEditingController _hex = TextEditingController(
    text: profileColorToHex(widget.initialColor),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(Color color) {
    setState(() {
      _selected = color;
      _hex.text = profileColorToHex(color);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose color'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _presets)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _setColor(color),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          width: color == _selected ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _hex,
              maxLength: 7,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Hex color',
                hintText: '#5860C3',
              ),
              onChanged: (value) {
                final parsed = profileColorFromHex(value, _selected);
                if (value.replaceFirst('#', '').length == 6) {
                  setState(() => _selected = parsed);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: context.pop, child: const Text('Cancel')),
        FilledButton(
          onPressed: () => context.pop(_selected),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}

class _MentionDialog extends StatefulWidget {
  const _MentionDialog();

  @override
  State<_MentionDialog> createState() => _MentionDialogState();
}

class _MentionDialogState extends State<_MentionDialog> {
  final _username = TextEditingController();
  final _tag = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add person'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _username,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixText: '@',
            ),
          ),
          TextField(
            controller: _tag,
            maxLength: 15,
            decoration: const InputDecoration(
              labelText: 'Your tag',
              hintText: 'Bestie, BF, …',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: context.pop, child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final username = _username.text.trim().replaceFirst('@', '');
            final tag = _tag.text.trim();
            if (username.isEmpty || tag.isEmpty || tag.length > 15) return;
            context.pop(
              ProfileMention(
                username: username,
                displayName: username,
                tag: tag,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
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

String _contentType(String extension) => switch (extension) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

Future<String> _uploadImage({
  required String bucket,
  required String userId,
  required String fileName,
  required Uint8List bytes,
  required String extension,
}) async {
  final storage = Supabase.instance.client.storage.from(bucket);
  final path = '$userId/$fileName';
  await storage.uploadBinary(
    path,
    bytes,
    fileOptions: FileOptions(
      upsert: true,
      contentType: _contentType(extension),
      cacheControl: '3600',
    ),
  );
  return '${storage.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
}

Future<void> _clearStorageFolder(String bucket, String userId) async {
  final storage = Supabase.instance.client.storage.from(bucket);
  final files = await storage.list(path: userId);
  if (files.isNotEmpty) {
    await storage.remove([for (final file in files) '$userId/${file.name}']);
  }
}
