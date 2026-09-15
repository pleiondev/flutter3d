/// Every address the service answers, and what it does with each.
///
/// **Pages are GETs, changes are POSTs, and a POST answers with a redirect.**
/// A form that re-renders itself on success leaves a page that a reload submits
/// again; a 303 to the page that shows the result does not. The only POSTs that
/// render are the ones that failed, because the person needs the form back with
/// what they typed still in it.
library;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/accounts.dart';
import '../db/models_repository.dart';
import '../db/rate_limit.dart';
import '../db/sessions_repository.dart';
import '../domain/access.dart';
import '../domain/model.dart';
import '../domain/project.dart';
import '../domain/user.dart';
import '../pages/account_pages.dart';
import '../pages/explore_page.dart';
import '../pages/home.dart';
import '../pages/model_page.dart';
import '../pages/my_models.dart';
import '../pages/plain_pages.dart';
import '../pages/project_page.dart';
import '../pages/projects_page.dart';
import '../pages/settings_page.dart';
import '../services.dart';
import '../storage/inspect.dart';
import '../storage/png.dart';
import 'cookies.dart';
import 'learn_routes.dart';
import 'render.dart';
import 'request.dart';
import 'static_files.dart';

/// The largest preview picture accepted, in bytes.
///
/// A preview is a viewport screenshot the browser captures and re-encodes,
/// not a photograph — a few megabytes is already generous for one, and far
/// below `services.config.uploadLimitBytes`, which exists for whole model
/// files.
const _previewLimitBytes = 4 * 1024 * 1024;

/// How many published models the showcase shows at once, and how many more
/// `/explore`'s own "More" link asks for on each page after the first.
const _exploreLimit = 24;

Handler buildHandler(Services services) {
  final policy = services.cookies;
  final accounts = services.accounts;

  final router = Router(notFoundHandler: _notFound)
    ..get('/health', (Request request) => Response.ok('ok'))
    ..mount(
      '/assets/',
      staticDirectory(
        services.config.assetsDirectory,
        cacheControl: 'public, max-age=300',
      ),
    );

  // Nothing a Flutter build emits carries a hash in its name, so the viewer is
  // revalidated on every load — the lesson the documentation site learned when
  // an edge kept a bootstrap that named a file the new build no longer had.
  if (services.config.viewerDirectory case final viewer?) {
    router.mount('/app/', staticDirectory(viewer, cacheControl: 'no-cache'));
  }

  // --- pages anybody can open -----------------------------------------------

  router
    ..get(
      '/',
      (Request request) async =>
          htmlPage(HomePage(signedIn: await userOf(request))),
    )
    ..get(
      '/privacy',
      (Request request) async =>
          htmlPage(PrivacyPage(signedIn: await userOf(request))),
    )
    ..get('/explore', (Request request) async {
      final params = request.url.queryParameters;
      final rawQuery = params['q'];
      final query = (rawQuery == null || rawQuery.trim().isEmpty)
          ? null
          : rawQuery.trim();
      final category = Category.of(params['category']);
      final before = DateTime.tryParse(params['before'] ?? '');
      final models = await services.models.published(
        limit: _exploreLimit,
        before: before,
        category: category,
        search: query,
      );
      return htmlPage(
        ExplorePage(
          models: models,
          signedIn: await userOf(request),
          query: query,
          category: category,
          hasMore: models.length == _exploreLimit,
        ),
      );
    })
    ..mount('/learn/modeler/', learnRoutes());

  // --- registration ------------------------------------------------------------

  router
    ..get('/register', (Request request) async {
      if (await userOf(request) != null) return seeOther('/me');
      return htmlPage(RegisterPage(csrf: csrfOf(request)));
    })
    ..post('/register', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);

      final outcome = await accounts.register(
        email: form['email'] ?? '',
        password: form['password'] ?? '',
        passwordConfirmation: form['passwordConfirm'] ?? '',
        displayName: form['displayName'] ?? '',
        ip: clientIp(request),
        userAgent: request.headers['user-agent'],
      );
      return switch (outcome) {
        Registered(:final sessionToken) => seeOther(
          '/me?said=welcome',
          headers: {
            'set-cookie': policy.session(sessionToken, sessionLifetime),
          },
        ),
        RegisterInvalid(:final problems) => htmlPage(
          RegisterPage(
            csrf: csrfOf(request),
            problems: problems,
            email: form['email'] ?? '',
            displayName: form['displayName'] ?? '',
          ),
          status: 422,
        ),
        RegisterLimited() => htmlPage(
          const MessagePage(
            title: 'Too many accounts from here',
            body:
                'This address has created several accounts in the last hour. '
                'Try again later.',
          ),
          status: 429,
        ),
      };
    })
    ..get('/verify', (Request request) async {
      final token = request.url.queryParameters['token'] ?? '';
      final verified = token.isEmpty ? null : await accounts.verify(token);
      return htmlPage(
        VerifiedPage(
          signedIn: await userOf(request),
          confirmed: verified != null,
        ),
        status: verified == null ? 400 : 200,
      );
    })
    ..post('/verify/resend', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final user = await userOf(request);
      if (user == null) return seeOther('/login');
      final sent = await accounts.resendVerification(
        user,
        ip: clientIp(request),
      );
      return seeOther(
        sent ? '/me?said=verify-sent' : '/me?said=letters-limited',
      );
    });

  // --- signing in and out --------------------------------------------------------

  router
    ..get('/login', (Request request) async {
      final next = safeNext(request.url.queryParameters['next']);
      if (await userOf(request) != null) return seeOther(next);
      return htmlPage(
        SignInPage(
          csrf: csrfOf(request),
          next: next,
          said: request.url.queryParameters['said'],
        ),
      );
    })
    ..post('/login', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final next = safeNext(form['next']);

      final outcome = await accounts.signIn(
        email: form['email'] ?? '',
        password: form['password'] ?? '',
        ip: clientIp(request),
        userAgent: request.headers['user-agent'],
      );
      return switch (outcome) {
        SignedIn(:final sessionToken) => seeOther(
          next,
          headers: {
            'set-cookie': policy.session(sessionToken, sessionLifetime),
          },
        ),
        SignInRefused() => htmlPage(
          SignInPage(
            csrf: csrfOf(request),
            next: next,
            email: form['email'] ?? '',
            error: 'That address and password do not match an account.',
          ),
          status: 401,
        ),
        SignInLimited() => htmlPage(
          SignInPage(
            csrf: csrfOf(request),
            next: next,
            email: form['email'] ?? '',
            error:
                'Too many attempts. Wait fifteen minutes, or reset the password.',
          ),
          status: 429,
        ),
      };
    })
    ..post('/logout', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final token = cookiesOf(request)[policy.sessionName];
      if (token != null) await accounts.signOut(token);
      return seeOther(
        '/login?said=signed-out',
        headers: {'set-cookie': policy.clearSession()},
      );
    });

  // --- getting back in ------------------------------------------------------------

  router
    ..get(
      '/forgot',
      (Request request) async => htmlPage(ForgotPage(csrf: csrfOf(request))),
    )
    ..post('/forgot', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final email = form['email'] ?? '';
      if (!isPlausibleEmail(email.trim())) {
        return htmlPage(
          ForgotPage(
            csrf: csrfOf(request),
            email: email,
            error: 'That does not look like an email address.',
          ),
          status: 422,
        );
      }
      final allowed = await accounts.requestReset(
        email: email,
        ip: clientIp(request),
      );
      return allowed
          ? htmlPage(ForgotPage(csrf: csrfOf(request), sentTo: email.trim()))
          : htmlPage(
              ForgotPage(
                csrf: csrfOf(request),
                email: email,
                error:
                    'Several letters have gone out already. Check the inbox and '
                    'the spam folder, or try again in an hour.',
              ),
              status: 429,
            );
    })
    ..get('/reset', (Request request) async {
      final token = request.url.queryParameters['token'] ?? '';
      return htmlPage(ResetPage(csrf: csrfOf(request), token: token));
    })
    ..post('/reset', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final token = form['token'] ?? '';
      final outcome = await accounts.reset(
        token: token,
        password: form['password'] ?? '',
        passwordConfirmation: form['passwordConfirm'] ?? '',
      );
      return switch (outcome) {
        ResetDone() => seeOther(
          '/login?said=password-reset',
          headers: {'set-cookie': policy.clearSession()},
        ),
        ResetPasswordRefused(:final because) => htmlPage(
          ResetPage(csrf: csrfOf(request), token: token, error: because),
          status: 422,
        ),
        ResetLinkInvalid() => htmlPage(
          const MessagePage(
            title: 'This link no longer works',
            body:
                'Reset links work once and for an hour, and asking for a new '
                'letter retires the old one. Ask for another from the sign-in page.',
            action: ('Ask for a new link', '/forgot'),
          ),
          status: 400,
        ),
      };
    });

  // --- the cabinet ----------------------------------------------------------------

  router
    ..get('/me', (Request request) async {
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/me');
      return htmlPage(
        MyModelsPage(
          user: user,
          csrf: csrfOf(request),
          models: await services.models.ofOwner(user.id),
          projects: await services.projects.ofOwner(user.id),
          uploadLimitBytes: services.config.uploadLimitBytes,
          said: request.url.queryParameters['said'],
        ),
      );
    })
    ..post('/api/v1/models', (Request request) async {
      if (!scriptIsOurs(request)) {
        return json(403, {'error': 'This page is out of date. Reload it.'});
      }
      final user = await userOf(request);
      if (user == null) return json(401, {'error': 'Sign in again.'});
      if (!canUpload(user)) {
        return json(403, {'error': 'Confirm your address before uploading.'});
      }

      final fileName = Uri.decodeComponent(
        request.headers['x-filename'] ?? 'model',
      );
      final limit = services.config.uploadLimitBytes;
      final bytes = await readBody(request, limit: limit);
      if (bytes == null) {
        return json(413, {
          'error': '$fileName is larger than ${formatBytes(limit)}.',
        });
      }

      switch (await inspectUpload(bytes, fileName: fileName)) {
        case Rejected(:final because):
          return json(422, {'error': because});
        case Accepted(:final format, :final triangleCount):
          final hash = await services.blobs.put(bytes);
          final record = await services.models.create(
            ownerId: user.id,
            title: titleFromFileName(fileName),
            sourceFormat: format.column,
            triangleCount: triangleCount,
            source: StoredFile(
              blobSha256: hash,
              bytes: bytes.length,
              contentType: format.contentType,
              filename: _fileNameFor(fileName, format),
            ),
          );
          return json(201, {'id': record.id, 'path': record.path});
      }
    })
    ..post('/api/v1/models/<id|[0-9]+>/preview', (
      Request request,
      String id,
    ) async {
      if (!scriptIsOurs(request)) {
        return json(403, {'error': 'This page is out of date. Reload it.'});
      }
      final user = await userOf(request);
      final model = await services.models.byId(int.parse(id));
      // A preview is edited on a model that already exists, so this checks
      // `canEdit`, the same as `/m/<id>/describe` and `/m/<id>/delete` — never
      // `canUpload`, which only says whether the account may create new
      // models. Missing or somebody else's: 404 either way, never 403, so a
      // private model's id is not confirmed to somebody who cannot edit it.
      if (model == null || !canEdit(model, user)) {
        return _notFound(request, viewer: user);
      }

      if (!await services.limiter.allow(
        'preview:account:${user!.id}',
        RateRule.previewPerAccount,
      )) {
        return json(429, {
          'error': 'Too many preview pictures saved recently. Try again later.',
        });
      }

      // The picture must have been captured against the source file the model
      // currently has — not one an earlier save already replaced — so a stale
      // capture cannot silently attach itself to whatever the model is now.
      final source = await services.models.fileOf(model.id, FileKind.source);
      final sourceSha = request.headers['x-source-sha256'];
      if (source == null ||
          sourceSha == null ||
          sourceSha != source.blobSha256) {
        return json(409, {
          'error':
              'The model has changed since this picture was captured. Reload '
              'it and capture the preview again.',
        });
      }

      final bytes = await readBody(request, limit: _previewLimitBytes);
      if (bytes == null) {
        return json(413, {
          'error':
              'A preview picture must be smaller than '
              '${formatBytes(_previewLimitBytes)}.',
        });
      }

      switch (inspectPreviewPng(bytes)) {
        case PngRejected(:final because):
          return json(422, {'error': because});
        case PngAccepted():
          final hash = await services.blobs.put(bytes);
          final replaced = await services.models.setPreview(
            model.id,
            StoredFile(
              blobSha256: hash,
              bytes: bytes.length,
              contentType: 'image/png',
              filename: 'preview.png',
            ),
          );
          // The picture this one replaced, freed the same way `/m/<id>/delete`
          // frees its own files — only once nothing else still points at it.
          if (replaced != null &&
              replaced != hash &&
              !await services.models.isReferenced(replaced)) {
            await services.blobs.delete(replaced);
          }
          return json(200, {'hasPreview': true});
      }
    })
    ..post('/api/v1/models/<id|[0-9]+>/source', (
      Request request,
      String id,
    ) async {
      if (!scriptIsOurs(request)) {
        return json(403, {'error': 'This page is out of date. Reload it.'});
      }
      final user = await userOf(request);
      final model = await services.models.byId(int.parse(id));
      // Saving edits a model that already exists, so this checks `canEdit`,
      // the same as the preview endpoint above — never `canUpload`. Missing
      // or somebody else's: 404 either way, never 403.
      if (model == null || !canEdit(model, user)) {
        return _notFound(request, viewer: user);
      }

      if (!await services.limiter.allow(
        'source-save:account:${user!.id}',
        RateRule.sourceSavePerAccount,
      )) {
        return json(429, {
          'error': 'Too many saves recently. Try again later.',
        });
      }

      final fileName = Uri.decodeComponent(
        request.headers['x-filename'] ?? 'model',
      );
      final limit = services.config.uploadLimitBytes;
      final bytes = await readBody(request, limit: limit);
      if (bytes == null) {
        return json(413, {
          'error': '$fileName is larger than ${formatBytes(limit)}.',
        });
      }

      // The identical decode-and-validate `inspectUpload` runs on a fresh
      // upload — an edited document that fails to decode is refused the same
      // way, not a weaker check because it is "just an update". Nothing is
      // stored, and no revision is recorded, until this accepts the bytes.
      switch (await inspectUpload(bytes, fileName: fileName)) {
        case Rejected(:final because):
          return json(422, {'error': because});
        case Accepted(:final format, :final triangleCount):
          final hash = await services.blobs.put(bytes);
          // Keeps the new file as current and records a revision row in one
          // transaction. The blob this replaces is deliberately not freed
          // here — it now lives on as a revision, and `isReferenced` already
          // knows to keep it alive.
          final updated = await services.models.replaceSource(
            modelId: model.id,
            newSource: StoredFile(
              blobSha256: hash,
              bytes: bytes.length,
              contentType: format.contentType,
              filename: _fileNameFor(fileName, format),
            ),
            triangleCount: triangleCount,
            sourceFormat: format.column,
            actorUserId: user.id,
          );
          return json(200, {
            'id': updated.id,
            'path': updated.path,
            'triangleCount': updated.triangleCount,
            'sizeBytes': updated.sizeBytes,
          });
      }
    })
    ..get('/api/v1/models/<id|[0-9]+>/revisions', (
      Request request,
      String id,
    ) async {
      final viewer = await userOf(request);
      final model = await services.models.byId(int.parse(id));
      // Revision metadata — no bytes, just id/size/who/when — follows the
      // model's own visibility, the same as its page or its current file:
      // `canView`, not `canEdit`. The file each revision points at stays
      // owner-only, at the download route below.
      if (model == null || !canView(model, viewer)) {
        return _notFound(request, viewer: viewer);
      }
      final revisions = await services.models.revisionsOf(model.id);
      return json(200, [
        for (final revision in revisions)
          {
            'id': revision.id,
            'bytes': revision.bytes,
            'createdAt': revision.createdAt.toIso8601String(),
            'createdBy': revision.createdBy,
          },
      ]);
    });

  // --- one model --------------------------------------------------------------------

  router
    ..get('/m/<ref>', (Request request, String ref) async {
      final viewer = await userOf(request);
      final model = await _modelOf(services, ref);
      if (model == null || !canView(model, viewer)) {
        return _notFound(request, viewer: viewer);
      }
      // An old or hand-typed slug still finds the model; the address it is
      // shown at is the current one.
      if (ref != '${model.id}-${model.slug}') {
        return Response.movedPermanently(model.path);
      }
      // Revision history is owner-only on the page, the same as the download
      // route at `/files/<id>/revisions/<revisionId>`, so nothing is fetched
      // for a viewer who could not follow those links anyway.
      final revisions = canEdit(model, viewer)
          ? await services.models.revisionsOf(model.id)
          : const <RevisionRecord>[];
      // The owner's own projects, for the move form's select — the same
      // owner-only fetch as `revisions` above, for the same reason: nobody
      // else's page needs to know what projects the owner keeps.
      final ownerProjects = canEdit(model, viewer)
          ? await services.projects.ofOwner(model.ownerId)
          : const <ProjectRecord>[];
      // `tut-19`'s own preview capture needs the source's current hash to
      // send as `x-source-sha256` — the same staleness guard
      // `/api/v1/models/<id>/preview` already checks it against. Fetched for
      // every viewer, not just the owner, because [ModelPage] threads it into
      // `viewer.js`'s data attributes unconditionally, the same as `data-id`.
      final source = await services.models.fileOf(model.id, FileKind.source);
      return htmlPage(
        ModelPage(
          model: model,
          viewer: viewer,
          csrf: csrfOf(request),
          viewerAvailable: true,
          revisions: revisions,
          ownerProjects: ownerProjects,
          sourceSha: source?.blobSha256 ?? '',
          said: request.url.queryParameters['said'],
        ),
      );
    })
    ..post('/m/<id|[0-9]+>/describe', (Request request, String id) async {
      final form = await readForm(request);
      return _editing(services, request, form, id, (model) async {
        final title = (form['title'] ?? '').trim();
        await services.models.describe(
          model.id,
          title: title.isEmpty
              ? model.title
              : (title.length > 80 ? title.substring(0, 80) : title),
          description: (form['description'] ?? '').trim(),
        );
        final updated = await services.models.byId(model.id);
        return seeOther('${updated!.path}?said=described');
      });
    })
    ..post('/m/<id|[0-9]+>/delete', (Request request, String id) async {
      final form = await readForm(request);
      return _editing(services, request, form, id, (model) async {
        final hashes = await services.models.delete(model.id);
        for (final hash in hashes.toSet()) {
          if (!await services.models.isReferenced(hash)) {
            await services.blobs.delete(hash);
          }
        }
        return seeOther('/me?said=deleted');
      });
    })
    ..post('/m/<id|[0-9]+>/move', (Request request, String id) async {
      final form = await readForm(request);
      return _editing(services, request, form, id, (model) async {
        final raw = (form['project'] ?? '').trim();
        int? targetId;
        if (raw.isNotEmpty) {
          targetId = int.tryParse(raw);
          final target = targetId == null
              ? null
              : await services.projects.byId(targetId);
          // Ownership of the target project is checked here, before
          // `moveToProject` is ever called, so a foreign project reads as
          // the same clean 404 every other ownership refusal on this page
          // already gives — not a raw database error, and not a 403 that
          // would confirm the project exists at all.
          final viewer = await userOf(request);
          if (target == null || !canEditProject(target, viewer)) {
            return _notFound(request, viewer: viewer);
          }
        }
        await services.models.moveToProject(model.id, targetId);
        final updated = await services.models.byId(model.id);
        return seeOther('${updated!.path}?said=moved');
      });
    })
    ..post('/m/<id|[0-9]+>/publish', (Request request, String id) async {
      final form = await readForm(request);
      return _editing(services, request, form, id, (model) async {
        if (!await services.limiter.allow(
          'publish:account:${model.ownerId}',
          RateRule.publishPerAccount,
        )) {
          return htmlPage(
            MessagePage(
              title: 'Too many publish changes',
              body:
                  'This account has published or unpublished several models '
                  'recently. Try again later.',
              signedIn: await userOf(request),
            ),
            status: 429,
          );
        }
        // Posted strings, never trusted as-is — `Licence.of`/`Category.of`
        // return null for anything outside their own enum, and that is a
        // clean 422 with the form re-shown, the same as `/register`'s own
        // `RegisterInvalid` branch, rather than a value reaching the
        // database for its `check` constraint to catch.
        final licence = Licence.of(form['licence']);
        final category = Category.of(form['category']);
        if (licence == null || category == null) {
          return htmlPage(
            ModelPage(
              model: model,
              viewer: await userOf(request),
              csrf: csrfOf(request),
              viewerAvailable: true,
              revisions: await services.models.revisionsOf(model.id),
              ownerProjects: await services.projects.ofOwner(model.ownerId),
              sourceSha:
                  (await services.models.fileOf(
                    model.id,
                    FileKind.source,
                  ))?.blobSha256 ??
                  '',
              publishProblems: {
                if (licence == null) 'licence': 'Choose one of the licences.',
                if (category == null)
                  'category': 'Choose one of the categories.',
              },
              publishLicence: form['licence'],
              publishCategory: form['category'],
            ),
            status: 422,
          );
        }
        await services.models.publish(model.id, licence, category: category);
        final updated = await services.models.byId(model.id);
        return seeOther('${updated!.path}?said=published');
      });
    })
    ..post('/m/<id|[0-9]+>/unpublish', (Request request, String id) async {
      final form = await readForm(request);
      return _editing(services, request, form, id, (model) async {
        if (!await services.limiter.allow(
          'publish:account:${model.ownerId}',
          RateRule.publishPerAccount,
        )) {
          return htmlPage(
            MessagePage(
              title: 'Too many publish changes',
              body:
                  'This account has published or unpublished several models '
                  'recently. Try again later.',
              signedIn: await userOf(request),
            ),
            status: 429,
          );
        }
        await services.models.unpublish(model.id);
        final updated = await services.models.byId(model.id);
        return seeOther('${updated!.path}?said=unpublished');
      });
    })
    ..get('/files/<id|[0-9]+>/source', (Request request, String id) async {
      final viewer = await userOf(request);
      final model = await services.models.byId(int.parse(id));
      if (model == null || !canView(model, viewer)) {
        return _notFound(request, viewer: viewer);
      }
      final file = await services.models.fileOf(model.id, FileKind.source);
      if (file == null) return _notFound(request, viewer: viewer);
      return _serveBlob(services, request, file, public: model.isPublic);
    })
    ..get('/files/<id|[0-9]+>/preview', (Request request, String id) async {
      final viewer = await userOf(request);
      final model = await services.models.byId(int.parse(id));
      if (model == null || !canView(model, viewer)) {
        return _notFound(request, viewer: viewer);
      }
      final file = await services.models.fileOf(model.id, FileKind.preview);
      // No picture yet is a 404, the same as a model with no page to redirect
      // to — never an empty 200, which would be indistinguishable from a
      // picture that really is zero bytes.
      if (file == null) return _notFound(request, viewer: viewer);
      return _serveBlob(services, request, file, public: model.isPublic);
    })
    ..get('/files/<id|[0-9]+>/revisions/<revisionId|[0-9]+>', (
      Request request,
      String id,
      String revisionId,
    ) async {
      final viewer = await userOf(request);
      final model = await services.models.byId(int.parse(id));
      // A past revision is an editing/audit artifact, not something a public
      // viewer should be able to enumerate-and-download even if the current
      // file is public — `canEdit`, owner-only, unlike the source and
      // preview downloads above.
      if (model == null || !canEdit(model, viewer)) {
        return _notFound(request, viewer: viewer);
      }
      final file = await services.models.revisionFile(
        model.id,
        int.parse(revisionId),
      );
      // Null both when the id does not exist at all and when it belongs to
      // a different model — `revisionFile` checks the two together, so
      // neither case can serve a file that is not this model's own.
      if (file == null) return _notFound(request, viewer: viewer);
      return _serveBlob(services, request, file, public: false);
    });

  // --- projects ---------------------------------------------------------------------

  router
    ..get('/projects', (Request request) async {
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/projects');
      return htmlPage(
        ProjectsPage(
          user: user,
          csrf: csrfOf(request),
          projects: await services.projects.ofOwner(user.id),
          said: request.url.queryParameters['said'],
        ),
      );
    })
    ..post('/projects', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/projects');
      final title = (form['title'] ?? '').trim();
      final created = await services.projects.create(
        ownerId: user.id,
        title: title.isEmpty
            ? 'Untitled project'
            : (title.length > 80 ? title.substring(0, 80) : title),
      );
      return seeOther('${created.path}?said=project-created');
    })
    ..get('/p/<ref>', (Request request, String ref) async {
      final viewer = await userOf(request);
      final project = await _projectOf(services, ref);
      // A project has no public side at all — `canEditProject` is also the
      // whole of "may this viewer even see it", the same as
      // `domain/access.dart` already says of it.
      if (project == null || !canEditProject(project, viewer)) {
        return _notFound(request, viewer: viewer);
      }
      if (ref != '${project.id}-${project.slug}') {
        return Response.movedPermanently(project.path);
      }
      return htmlPage(
        ProjectPage(
          project: project,
          viewer: viewer!,
          csrf: csrfOf(request),
          models: await services.models.ofProject(project.id),
          said: request.url.queryParameters['said'],
        ),
      );
    })
    ..post('/p/<id|[0-9]+>/describe', (Request request, String id) async {
      final form = await readForm(request);
      return _editingProject(services, request, form, id, (project) async {
        final title = (form['title'] ?? '').trim();
        await services.projects.describe(
          project.id,
          title: title.isEmpty
              ? project.title
              : (title.length > 80 ? title.substring(0, 80) : title),
          description: (form['description'] ?? '').trim(),
        );
        final updated = await services.projects.byId(project.id);
        return seeOther('${updated!.path}?said=described');
      });
    })
    ..post('/p/<id|[0-9]+>/delete', (Request request, String id) async {
      final form = await readForm(request);
      return _editingProject(services, request, form, id, (project) async {
        await services.projects.delete(project.id);
        return seeOther('/projects?said=project-deleted');
      });
    });

  // --- settings ----------------------------------------------------------------------

  router
    ..get('/settings', (Request request) async {
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/settings');
      return htmlPage(
        SettingsPage(
          user: user,
          csrf: csrfOf(request),
          said: request.url.queryParameters['said'],
        ),
      );
    })
    ..post('/settings/name', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/settings');
      final name = (form['displayName'] ?? '').trim();
      if (name.isEmpty || name.length > 60) {
        return htmlPage(
          SettingsPage(
            user: user,
            csrf: csrfOf(request),
            nameError: 'A name between 1 and 60 characters.',
          ),
          status: 422,
        );
      }
      await services.users.setDisplayName(user.id, name);
      return seeOther('/settings?said=name-saved');
    })
    ..post('/settings/password', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/settings');
      final refused = await accounts.changePassword(
        user,
        current: form['current'] ?? '',
        next: form['next'] ?? '',
        confirmation: form['nextConfirm'] ?? '',
      );
      if (refused != null) {
        return htmlPage(
          SettingsPage(
            user: user,
            csrf: csrfOf(request),
            passwordError: refused,
          ),
          status: 422,
        );
      }
      // Every session ended with the change, this one included, so the person
      // signs in again with the password they just chose.
      return seeOther(
        '/login?said=password-changed',
        headers: {'set-cookie': policy.clearSession()},
      );
    })
    ..post('/settings/delete', (Request request) async {
      final form = await readForm(request);
      if (!formIsOurs(request, form, policy)) return _staleForm(request);
      final user = await userOf(request);
      if (user == null) return seeOther('/login?next=/settings');
      final deleted = await accounts.deleteAccount(
        user,
        password: form['password'] ?? '',
      );
      if (!deleted) {
        return htmlPage(
          SettingsPage(
            user: user,
            csrf: csrfOf(request),
            deleteError: 'That password is not right.',
          ),
          status: 422,
        );
      }
      return seeOther(
        '/?said=account-deleted',
        headers: {'set-cookie': policy.clearSession()},
      );
    });

  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_securityHeaders())
      .addMiddleware(csrfCookie(policy))
      .addHandler(router.call);
}

Future<Response> _editing(
  Services services,
  Request request,
  Map<String, String> form,
  String id,
  Future<Response> Function(ModelRecord model) change,
) async {
  if (!formIsOurs(request, form, services.cookies)) return _staleForm(request);
  final user = await userOf(request);
  final model = await services.models.byId(int.parse(id));
  if (model == null || !canEdit(model, user)) {
    return _notFound(request, viewer: user);
  }
  return change(model);
}

Future<ModelRecord?> _modelOf(Services services, String ref) async {
  final id = int.tryParse(RegExp(r'^\d+').stringMatch(ref) ?? '');
  return id == null ? null : services.models.byId(id);
}

Future<Response> _editingProject(
  Services services,
  Request request,
  Map<String, String> form,
  String id,
  Future<Response> Function(ProjectRecord project) change,
) async {
  if (!formIsOurs(request, form, services.cookies)) return _staleForm(request);
  final user = await userOf(request);
  final project = await services.projects.byId(int.parse(id));
  if (project == null || !canEditProject(project, user)) {
    return _notFound(request, viewer: user);
  }
  return change(project);
}

Future<ProjectRecord?> _projectOf(Services services, String ref) async {
  final id = int.tryParse(RegExp(r'^\d+').stringMatch(ref) ?? '');
  return id == null ? null : services.projects.byId(id);
}

Future<Response> _serveBlob(
  Services services,
  Request request,
  StoredFile file, {
  required bool public,
}) async {
  final etag = '"${file.blobSha256}"';
  // Content-addressed, so the tag is the content: if the browser holds these
  // bytes, they are exactly the bytes it would be sent.
  final cache = public ? 'public, max-age=300' : 'private, no-cache';
  if (request.headers['if-none-match'] == etag) {
    return Response.notModified(
      headers: {'etag': etag, 'cache-control': cache},
    );
  }
  final stream = await services.blobs.open(file.blobSha256);
  if (stream == null) {
    return Response.internalServerError(body: 'The file is missing.');
  }

  final inline = request.url.queryParameters.containsKey('inline');
  final name = file.filename.replaceAll('"', '');
  return Response.ok(
    stream,
    headers: {
      'content-type': file.contentType,
      'content-length': '${file.bytes}',
      'etag': etag,
      'cache-control': cache,
      'content-disposition': inline
          ? 'inline'
          : 'attachment; filename="$name"; filename*=UTF-8\'\'${Uri.encodeComponent(file.filename)}',
    },
  );
}

String _fileNameFor(String uploaded, SourceFormat format) {
  final base = uploaded.split(RegExp(r'[/\\]')).last.trim();
  final safe = base.replaceAll(RegExp(r'[\x00-\x1f"]'), '');
  if (safe.isEmpty) return 'model${format.suffix}';
  return safe.toLowerCase().endsWith(format.suffix)
      ? safe
      : '$safe${format.suffix}';
}

Future<Response> _notFound(Request request, {User? viewer}) async => htmlPage(
  NotFoundPage(signedIn: viewer ?? await userOf(request)),
  status: 404,
);

/// A form whose token does not match — almost always a page left open across
/// a sign-out or a restart of the browser, rarely an attack. Either way the
/// answer is the same page, and it does not say which.
Future<Response> _staleForm(Request request) async => htmlPage(
  MessagePage(
    title: 'This page was out of date',
    body:
        'The form was sent from a page opened before something changed — a '
        'sign-out, or cookies being cleared. Go back, reload, and send it again.',
    signedIn: await userOf(request),
  ),
  status: 403,
);

Middleware _securityHeaders() =>
    (Handler inner) => (Request request) async {
      final response = await inner(request);
      final isPage =
          response.headers['content-type']?.startsWith('text/html') ?? false;
      final isViewer = request.url.path.startsWith('app/');
      return response.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'same-origin',
          if (isPage && !isViewer) ...{
            // Nothing inline and nothing from elsewhere: every script and style is a
            // file under /assets/, so a string that got into a page through a model
            // title has nothing it can run.
            'content-security-policy':
                "default-src 'self'; img-src 'self' data:; style-src 'self'; "
                "script-src 'self'; frame-src 'self'; frame-ancestors 'none'; "
                "form-action 'self'; base-uri 'self'; object-src 'none'",
            'x-frame-options': 'DENY',
          },
          if (isViewer) 'x-frame-options': 'SAMEORIGIN',
          if (request.requestedUri.scheme == 'https' ||
              request.headers['x-forwarded-proto'] == 'https')
            'strict-transport-security': 'max-age=31536000',
        },
      );
    };
