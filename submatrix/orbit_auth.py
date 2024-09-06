import sys
import pycurl
from synapse import types


def check_credentials(username, password):
    auth_url = 'http://orbit:9098/mail_auth'
    headers = [
        f'Auth-User: {username}',
        f'Auth-Pass: {password}',
        'Auth-Protocol: smtp',
        'Auth-Method: plain',
    ]

    credential_client = pycurl.Curl()
    credential_client.setopt(credential_client.URL, auth_url)
    credential_client.setopt(credential_client.HTTPHEADER, headers)

    try:
        credential_client.perform()
        return 200 == credential_client.getinfo(pycurl.RESPONSE_CODE)
    except pycurl.error as e:
        print(f'error: request failed: {e}', file=sys.stderr)
        return False
    finally:
        credential_client.close()


class OrbitAuthProvider:
    def __init__(self, _, api):

        self.api = api

        api.register_password_auth_provider_callbacks(
                auth_checkers={("m.login.password", ("password",)):
                               self.handle_login})

    async def handle_login(self, input_username, login_type, login_dict):
        # This should be impossible, because we only provide this
        # callback for m.login.passwordlogin attempts, but it is worth checking
        if login_type != "m.login.password":
            return None

        # Check if the input string was sent in the form of a fully qualified
        # domain specific string that can be parsed into a matrix username and
        # that the domain name is sane
        if types.UserID.is_valid(input_username):

            # Should not throw because valid check passed above
            user_id_obj = types.UserID.from_string(input_username)

            # Check that username contains a hostname, and
            # that that hostname matches the matrix server
            if not self.api.is_mine(user_id_obj):
                return None

            # given a username in canonical format of "@<username>:<domain>"
            # only the username part is Orbit ID. No empty usernames allowed
            if not (username := user_id_obj.localpart):
                return None

            user_id = user_id_obj.to_string()

        else:

            username = types.map_username_to_mxid_localpart(input_username)

            user_id = self.api.get_qualified_user_id(username)

        # No empty passwords allowed
        if not (password := login_dict.get("password", None)):
            return None

        # Ask orbit whether these credentials are valid
        if not check_credentials(username, password):
            return None

        # Look up existing record for user (matrix usernames are not
        # case sensistive) and return canonical capitalization of it
        existing_user = await self.api.check_user_exists(user_id)
        if existing_user is not None:
            return (existing_user, None)

        # If there is no existing user, lazily register their orbit ID with
        # synapse so that orbit maintains absolute control over credentials
        new_user = await self.api.register_user(username, username)
        return (new_user, None)
