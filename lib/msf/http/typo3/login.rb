# -*- coding: binary -*-
module Msf::HTTP::Typo3::Login

  # performs a typo3 backend login
  #
  # @param user [String] Username
  # @param pass [String] Password
  # @return [String,nil] the session cookies as a single string on successful login, nil otherwise
  def typo3_backend_login(user, pass)
    # get login page for RSA modulus and exponent
    res_main = send_request_cgi({
      'method' => 'GET',
      'uri' => typo3_url_login
    })

    unless res_main and res_main.code == 200
      vprint_error('Can not reach login page')
      return nil
    end

    e = res_main.body.match(/<input type="hidden" id="rsa_e" name="e" value="(\d+)" \/>/)[1]
    n = res_main.body.match(/<input type="hidden" id="rsa_n" name="n" value="(\w+)" \/>/)[1]
    vprint_debug("e: #{e}")
    vprint_debug("n: #{n}")
    rsa_enc = typo3_helper_login_rsa(e, n, pass)
    vprint_debug("RSA Hash: #{rsa_enc}")
    # make login request
    vars_post = {
      'n' => '',
      'e' => '',
      'login_status' => 'login',
      'userident' => rsa_enc,
      'redirect_url' => 'backend.php',
      'loginRefresh' => '',
      'interface' => 'backend',
      'username' => user,
      'p_field' => '',
      'commandLI' => 'Login'
    }
    res_login = send_request_cgi({
      'method' => 'POST',
      'uri' => typo3_url_login,
      'cookie' => res_main.get_cookies,
      'vars_post' => vars_post,
      'headers' => {'Referer' => full_uri}
    })
    if res_login
      if res_login.body =~ /<!-- ###LOGIN_ERROR### begin -->(.*)<!-- ###LOGIN_ERROR### end -->/im
        vprint_debug(strip_tags($1))
        return nil
      elsif res_login.body =~ /<p class="t3-error-text">(.*?)<\/p>/im
        vprint_debug(strip_tags($1))
        return nil
      else
        cookies = res_login.get_cookies
        return cookies if typo3_admin_cookie_valid?(cookies)
        return nil
      end
    end

    return nil
  end

  # verifies cookies by calling the backend and checking the response
  #
  # @param cookiestring [String] The http cookies as a concatenated string
  # @return [Boolean] true if the cookie is valid, false otherwise
  def typo3_admin_cookie_valid?(cookiestring)
    res_check = send_request_cgi({
      'method' => 'GET',
      'uri' => typo3_url_backend,
      'cookie' => cookiestring,
      'headers' => {'Referer' => full_uri}
    })
    return true if res_check and res_check.code == 200 and res_check.body and res_check.body =~ /<body [^>]+ id="typo3-backend-php">/
    return false
  end

  private

  # encrypts the password with the public key for login
  #
  # @param e [String] The exponent extracted from the login page
  # @param n [String] The modulus extracted from the login page
  # @param password [String] The clear text password to encrypt
  # @return [String] the base64 encoded password with prefixed 'rsa:'
  def typo3_helper_login_rsa(e, n, password)
    key = OpenSSL::PKey::RSA.new
    exponent = OpenSSL::BN.new e.hex.to_s
    modulus = OpenSSL::BN.new n.hex.to_s
    key.e = exponent
    key.n = modulus
    enc = key.public_encrypt(password)
    enc_b64 = Rex::Text.encode_base64(enc)
    "rsa:#{enc_b64}"
  end

end
