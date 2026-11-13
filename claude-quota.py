"""Read only Claude quota windows; credentials never leave memory or reach stdout."""
import getpass
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import unicodedata
import urllib.request


def read_quota(status):
    path = os.environ.get('PATH', '') + os.pathsep + os.path.expanduser('~/.local/bin') + ':/opt/homebrew/bin:/usr/local/bin'
    if not shutil.which('claude', path=path):
        return {}
    default = os.path.expanduser('~/.claude')
    root = os.environ.get('CLAUDE_SECURESTORAGE_CONFIG_DIR', os.environ.get('CLAUDE_CONFIG_DIR', default)) or default
    service = 'Claude Code-credentials'
    if root != default:
        service += '-' + hashlib.sha256(unicodedata.normalize('NFC', root).encode()).hexdigest()[:8]
    result = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', service,
                             '-a', getpass.getuser(), '-w'], capture_output=True, timeout=10)
    if result.returncode != 0:
        return {}
    oauth = json.loads(result.stdout).get('claudeAiOauth', {})
    token = oauth.get('accessToken')
    if not isinstance(token, str) or not token:
        return {}
    plan = oauth.get('subscriptionType')
    if isinstance(plan, str) and plan and plan != 'unknown':
        status['subscription'] = plan
    request = urllib.request.Request('https://api.anthropic.com/api/oauth/usage', headers={
        'Authorization': 'Bearer ' + token,
        'anthropic-beta': 'oauth-2025-04-20',
        'User-Agent': 'projector-overlay/0.1'
    })
    # Do not forward authentication to a redirect destination.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
        status["authorization"] = "Signed in"
        data = response.read(65537)
        if len(data) > 65536:
            return {}
        payload = json.loads(data)
        source = payload.get('rate_limits', payload)
        return {key: {field: source[key][field] for field in ('utilization', 'used_percentage', 'resets_at')
                      if field in source[key]}
                for key in ('five_hour', 'seven_day') if isinstance(source.get(key), dict)}


if __name__ == '__main__':
    status = {}
    quota = {}
    try:
        quota = read_quota(status)
    except urllib.error.HTTPError as error:
        if error.code == 401:
            status['authorization'] = 'Credentials rejected'
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    print(json.dumps(dict(status, quota=quota) if '--status' in sys.argv else quota))
