/**
 * OTP Sender Service
 *
 * SMS delivery via Twilio. Development uses console logging.
 */

import twilio from 'twilio';
import config from '../config/index.js';
import logger from '../utils/logger.js';

const SMS_PROVIDER = {
  TWILIO: 'twilio',
  CONSOLE: 'console',
};

class OTPSenderService {
  constructor() {
    this.provider = this.determineProvider();
    this._twilioClient = null;
    logger.info(`OTP Sender initialized with provider: ${this.provider}`);
  }

  _getTwilioClient() {
    const { accountSid, authToken } = config.twilio;
    if (!accountSid || !authToken) return null;
    if (!this._twilioClient) {
      this._twilioClient = twilio(accountSid, authToken);
    }
    return this._twilioClient;
  }

  _smsFromNumber() {
    return config.twilio.smsFrom || config.twilio.phoneNumber;
  }

  determineProvider() {
    if (config.env !== 'production') {
      return SMS_PROVIDER.CONSOLE;
    }

    const from = this._smsFromNumber();
    if (config.twilio.accountSid && config.twilio.authToken && from) {
      return SMS_PROVIDER.TWILIO;
    }

    logger.warn(
      'Twilio SMS not configured for production (need TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_PHONE_NUMBER or TWILIO_SMS_FROM). OTPs will not be delivered.'
    );
    return SMS_PROVIDER.CONSOLE;
  }

  /**
   * @param {string} phoneNumber - digits without country code
   * @param {string} otp
   * @param {string} countryCode - default '91'
   * @param {string|null} [smsAppHash] - Android SMS Retriever 11-char hash (optional)
   */
  async sendOtp(phoneNumber, otp, countryCode = '91', smsAppHash = null) {
    const sanitizedPhone = phoneNumber.replace(/\D/g, '').replace(/^0+/, '');
    const cc = countryCode.replace('+', '').replace(/\D/g, '');

    switch (this.provider) {
      case SMS_PROVIDER.TWILIO:
        await this.sendViaTwilio(sanitizedPhone, otp, cc, smsAppHash);
        break;
      case SMS_PROVIDER.CONSOLE:
      default:
        this.logToConsole(sanitizedPhone, otp, cc, smsAppHash);
        break;
    }
  }

  /**
   * E.164 for Twilio (e.g. +919876543210)
   */
  _toE164(sanitizedLocalDigits, countryDigits) {
    return `+${countryDigits}${sanitizedLocalDigits}`;
  }

  _buildSmsBody(otp, smsAppHash) {
    const line1 = `<#> Your Jobtree code is ${otp}. Valid ${config.otp.expiryMinutes} min. Do not share.`;
    if (smsAppHash && /^[A-Za-z0-9+/=-]{11}$/.test(smsAppHash)) {
      return `${line1}\n${smsAppHash}`;
    }
    return `Your Jobtree verification code is ${otp}. Valid for ${config.otp.expiryMinutes} minutes. Do not share this code.`;
  }

  async sendViaTwilio(sanitizedPhone, otp, countryDigits, smsAppHash = null) {
    const client = this._getTwilioClient();
    const from = this._smsFromNumber();
    if (!client || !from) {
      throw new Error('Twilio SMS is not configured.');
    }

    const to = this._toE164(sanitizedPhone, countryDigits);
    const body = this._buildSmsBody(otp, smsAppHash);

    try {
      await client.messages.create({
        body,
        from,
        to,
      });
      logger.info(`Twilio SMS: OTP sent to ${this.maskPhone(to)}`);
    } catch (error) {
      logger.error('Twilio SMS error:', {
        code: error.code,
        message: error.message,
        to: this.maskPhone(to),
      });
      throw new Error('Failed to send OTP. Please try again.');
    }
  }

  logToConsole(sanitizedPhone, otp, countryDigits, smsAppHash = null) {
    if (config.env === 'production') {
      logger.error('SECURITY: Production OTP with console provider — SMS not delivered');
      return;
    }

    const formattedNumber = this._toE164(sanitizedPhone, countryDigits);
    const previewBody = this._buildSmsBody(otp, smsAppHash);

    logger.warn(`[DEV MODE] OTP for ${formattedNumber}: ${otp}`);

    console.log(`
╔══════════════════════════════════════════════════════════════╗
║                    📱 DEV MODE OTP                           ║
╠══════════════════════════════════════════════════════════════╣
║  Phone: ${formattedNumber.padEnd(52)}║
║  OTP:   ${otp.padEnd(52)}║
║  SMS body (use for Android SMS Retriever tests):            ║
${previewBody.split('\n').map((l) => `║  ${l.padEnd(58)}║`).join('\n')}
║  Expires in: ${config.otp.expiryMinutes} minutes                                      ║
╚══════════════════════════════════════════════════════════════╝
    `);
  }

  maskPhone(phone) {
    if (!phone || phone.length < 6) return '****';
    return phone.slice(0, 4) + '****' + phone.slice(-2);
  }

  getProvider() {
    return this.provider;
  }

  isConfigured() {
    if (config.env !== 'production') return true;
    return this.provider === SMS_PROVIDER.TWILIO;
  }
}

export default new OTPSenderService();
