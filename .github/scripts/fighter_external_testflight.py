#!/usr/bin/env python3
"""Submit the verified external candidate to existing active TestFlight groups.

Never create testers/public links, change contacts, or repeat a pending review.
Reports contain group counts and readiness booleans, not identities or contacts.
"""
from urllib.parse import urlencode
import asc_promote as asc


def require(value, message):
    if not value:
        raise ValueError(message)


def listing(path):
    rows = []
    for _ in range(20):
        response = asc.call('GET', path)
        rows.extend(response.get('data', []))
        following = response.get('links', {}).get('next')
        if not following:
            return rows
        prefix = 'https://api.appstoreconnect.apple.com/v1'
        require(following.startswith(prefix + '/'), 'Unexpected pagination destination')
        path = following[len(prefix):]
    raise ValueError('Unbounded external group listing')


def inspect(request):
    require(request.get('channel') == 'testflight-external', 'External request required')
    require(request.get('external_group_policy') == 'existing-active-external', 'Existing group policy required')
    apps = listing('/apps?' + urlencode({'filter[bundleId]': request['bundle_id']}))
    require(len(apps) == 1, 'Expected exact existing app')
    app_id = apps[0]['id']
    groups = []
    for group in listing(f'/apps/{app_id}/betaGroups?limit=200'):
        if group['attributes'].get('isInternalGroup') is not False:
            continue
        builds = listing(f"/betaGroups/{group['id']}/builds?limit=200")
        if any(b['attributes'].get('processingState') == 'VALID' and
               b['attributes'].get('expired') is False for b in builds):
            groups.append({'id': group['id'], 'name': group['attributes']['name']})
    localizations = listing(f'/apps/{app_id}/betaAppLocalizations?limit=200')
    descriptions_ready = bool(localizations) and all(
        (row['attributes'].get('description') or '').strip() for row in localizations)
    detail = asc.call('GET', f'/apps/{app_id}/betaAppReviewDetail').get('data')
    attributes = detail.get('attributes', {}) if detail else {}
    contacts_ready = all(attributes.get(key) for key in (
        'contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'))
    account_ready = not attributes.get('demoAccountRequired') or all(
        attributes.get(key) for key in ('demoAccountName', 'demoAccountPassword'))
    asc.save_report('promotion-external-preflight.json', request, app_id=app_id,
                    external_group_count=len(groups), descriptions_ready=descriptions_ready,
                    review_contacts_ready=contacts_ready, review_account_ready=account_ready)
    require(groups, 'No existing active external group; no audience was created')
    require(descriptions_ready and contacts_ready and account_ready,
            'Existing TestFlight review metadata is incomplete; see readiness report')
    return app_id, groups


def submit(request):
    require(request.get('notify_external_testers') is True, 'External notification authorization required')
    _, groups = inspect(request)
    build = asc.find_build(request)
    require(build is not None and build['attributes'].get('processingState') == 'VALID',
            'Exact build is not ready')
    require(build['attributes'].get('buildAudienceType') == 'APP_STORE_ELIGIBLE',
            'Apple still marks this build INTERNAL_ONLY; external submission refused')
    build_id = build['id']
    path = f'/builds/{build_id}/buildBetaDetail'
    detail = asc.call('GET', path)['data']
    state = detail['attributes'].get('externalBuildState')
    acceptable = {'READY_FOR_BETA_SUBMISSION', 'WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW',
                  'BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'}
    require(state in acceptable, 'External build needs attention: ' + str(state))
    if detail['attributes'].get('autoNotifyEnabled') is not True:
        asc.call('PATCH', f"/buildBetaDetails/{detail['id']}", {'data': {
            'type': 'buildBetaDetails', 'id': detail['id'], 'attributes': {'autoNotifyEnabled': True}}})
    # Attach only missing relationships. This does not invite or create people.
    linked_ids = {group['id'] for group in groups if any(
        row['id'] == build_id for row in listing(f"/betaGroups/{group['id']}/relationships/builds?limit=200"))}
    missing = [{'type': 'betaGroups', 'id': group['id']} for group in groups if group['id'] not in linked_ids]
    if missing:
        asc.call('POST', f'/builds/{build_id}/relationships/betaGroups', {'data': missing})
    detail = asc.call('GET', path)['data']
    state = detail['attributes'].get('externalBuildState')
    submitted = False
    if state == 'READY_FOR_BETA_SUBMISSION':
        existing = listing('/betaAppReviewSubmissions?' + urlencode({'filter[build]': build_id, 'limit': 200}))
        require(not existing, 'An existing review requires reconciliation; do not submit twice')
        asc.call('POST', '/betaAppReviewSubmissions', {'data': {
            'type': 'betaAppReviewSubmissions',
            'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
        submitted = True
    actual = {group['id'] for group in groups if any(
        row['id'] == build_id for row in listing(f"/betaGroups/{group['id']}/relationships/builds?limit=200"))}
    require(all(group['id'] in actual for group in groups), 'External group association did not persist')
    detail = asc.call('GET', path)['data']['attributes']
    require(detail.get('autoNotifyEnabled') is True, 'Automatic external notifications were not enabled')
    asc.save_report('promotion-external-status.json', request, build_id=build_id,
                    build_audience_type=build['attributes']['buildAudienceType'],
                    external_group_count=len(groups), groups_verified=True, auto_notify_enabled=True,
                    submitted_this_run=submitted, external_build_state=detail.get('externalBuildState'),
                    internal_build_state=detail.get('internalBuildState'),
                    installable_now=detail.get('externalBuildState') == 'IN_BETA_TESTING')
