# Copyright (C) 2012-2023 Zammad Foundation, https://zammad-foundation.org/

class SecureMailing::SMIME::Outgoing < SecureMailing::Backend::HandlerOutgoing
  def type
    'S/MIME'
  end

  def signed
    from       = mail.from.first
    cert_model = SMIMECertificate.for_sender_email_address(from)
    raise "Unable to find ssl private key for '#{from}'" if !cert_model
    raise "Expired certificate for #{from} (fingerprint #{cert_model.fingerprint}) with #{cert_model.not_before_at} to #{cert_model.not_after_at}" if !security[:sign][:allow_expired] && cert_model.expired?

    private_key = OpenSSL::PKey::RSA.new(cert_model.private_key, cert_model.private_key_secret)

    Mail.new(OpenSSL::PKCS7.write_smime(OpenSSL::PKCS7.sign(cert_model.parsed, private_key, mail.encoded, chain(cert_model), OpenSSL::PKCS7::DETACHED)))
  rescue => e
    log('sign', 'failed', e.message)
    raise
  end

  def chain(cert)
    lookup_issuer = cert.parsed.issuer.to_s

    result = []
    loop do
      found_cert = SMIMECertificate.find_by(subject: lookup_issuer)
      break if found_cert.blank?

      subject       = found_cert.parsed.subject.to_s
      lookup_issuer = found_cert.parsed.issuer.to_s

      result.push(found_cert.parsed)

      # we've reached the root CA
      break if subject == lookup_issuer
    end
    result
  end

  def encrypt(data)
    expired_cert = certificates.detect(&:expired?)
    raise "Expired certificates for cert with #{expired_cert.not_before_at} to #{expired_cert.not_after_at}" if !security[:encryption][:allow_expired] && expired_cert.present?

    Mail.new(OpenSSL::PKCS7.write_smime(OpenSSL::PKCS7.encrypt(certificates.map(&:parsed), data, cipher)))
  rescue => e
    log('encryption', 'failed', e.message)
    raise
  end

  def cipher
    @cipher ||= OpenSSL::Cipher.new('AES-128-CBC')
  end

  private

  def certificates
    certificates = []
    %w[to cc].each do |recipient|
      addresses = mail.send(recipient)
      next if !addresses

      certificates += SMIMECertificate.for_recipient_email_addresses!(addresses)
    end
    certificates
  end
end
