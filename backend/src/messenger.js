// Sends real messages: sign-in codes and gym broadcasts by SMS (MSG91), WhatsApp (Meta Cloud API) and email (Resend).
// Everything is configured by environment variables and only used when set; without them the development backend keeps
// logging codes and recording messages in the outbox. India's rules apply: SMS and WhatsApp messages must use templates
// the gym operator registered (DLT for SMS, Meta approval for WhatsApp); the template ids/names below are those.
import { ApiError } from './errors.js';

const digits = (phone) => String(phone).replace(/\D/g, '');

export class Messenger {
  constructor(config, fetchImpl = globalThis.fetch) {
    this.cfg = config.messaging ?? {};
    this.fetch = this.cfg.fetchImpl ?? fetchImpl;
    this.transport = this.cfg.transport ?? null; // tests: { sendOtp(), sendText() }
  }

  /** Which channels can deliver a sign-in code. */
  canSendOtp(channel) {
    if (this.transport) return true;
    if (channel === 'sms') return !!(this.cfg.sms?.provider === 'msg91' && this.cfg.sms.authKey && this.cfg.sms.otpTemplateId);
    if (channel === 'whatsapp') return !!(this.cfg.whatsapp?.token && this.cfg.whatsapp.phoneNumberId && this.cfg.whatsapp.otpTemplate);
    if (channel === 'email') return !!(this.cfg.email?.apiKey && this.cfg.email.from);
    return false;
  }

  /** Which channels can deliver a gym's free-text message (broadcasts, reminders, receipts). */
  canSendText(channel) {
    if (this.transport) return true;
    if (channel === 'sms') return !!(this.cfg.sms?.provider === 'msg91' && this.cfg.sms.authKey && this.cfg.sms.flowTemplateId);
    if (channel === 'whatsapp') return !!(this.cfg.whatsapp?.token && this.cfg.whatsapp.phoneNumberId && this.cfg.whatsapp.textTemplate);
    return false;
  }

  get anyText() { return this.canSendText('sms') || this.canSendText('whatsapp'); }

  async sendOtp({ channel, to, code }) {
    if (this.transport) return this.transport.sendOtp({ channel, to, code });
    if (channel === 'sms') return this._msg91Otp(to, code);
    if (channel === 'whatsapp') return this._whatsapp(to, this.cfg.whatsapp.otpTemplate, [code], { otpButton: code });
    if (channel === 'email') return this._email(to, 'Your Gymmie sign-in code', `Your Gymmie code is ${code}. It expires in 10 minutes. If you did not ask for it, ignore this email.`);
    throw new ApiError(501, 'OTP_PROVIDER_NOT_CONFIGURED', 'This way of receiving codes is not available');
  }

  async sendText({ channel, to, body }) {
    if (this.transport) return this.transport.sendText({ channel, to, body });
    if (channel === 'sms') return this._msg91Flow(to, body);
    if (channel === 'whatsapp') return this._whatsapp(to, this.cfg.whatsapp.textTemplate, [body]);
    throw new ApiError(501, 'PROVIDER_NOT_CONFIGURED', 'No provider for this channel');
  }

  async _json(url, init) {
    const res = await this.fetch(url, init);
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`provider ${res.status}: ${JSON.stringify(body).slice(0, 200)}`);
    return body;
  }

  async _msg91Otp(to, code) {
    const c = this.cfg.sms;
    const q = new URLSearchParams({ template_id: c.otpTemplateId, mobile: digits(to), authkey: c.authKey, otp: String(code) });
    const body = await this._json(`https://control.msg91.com/api/v5/otp?${q}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    if (body.type && body.type !== 'success') throw new Error(`msg91: ${body.message ?? body.type}`);
    return { providerId: body.request_id ?? null };
  }

  async _msg91Flow(to, text) {
    const c = this.cfg.sms;
    const body = await this._json('https://control.msg91.com/api/v5/flow/', {
      method: 'POST', headers: { authkey: c.authKey, 'content-type': 'application/json' },
      body: JSON.stringify({ template_id: c.flowTemplateId, short_url: 0, recipients: [{ mobiles: digits(to), var1: text }] }),
    });
    if (body.type && body.type !== 'success') throw new Error(`msg91: ${body.message ?? body.type}`);
    return { providerId: body.message ?? null };
  }

  async _whatsapp(to, template, params, { otpButton } = {}) {
    const c = this.cfg.whatsapp;
    const components = [{ type: 'body', parameters: params.map((text) => ({ type: 'text', text: String(text) })) }];
    if (otpButton) components.push({ type: 'button', sub_type: 'url', index: '0', parameters: [{ type: 'text', text: String(otpButton) }] });
    const body = await this._json(`https://graph.facebook.com/${c.apiVersion ?? 'v20.0'}/${c.phoneNumberId}/messages`, {
      method: 'POST', headers: { authorization: `Bearer ${c.token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to: digits(to), type: 'template', template: { name: template, language: { code: c.language ?? 'en' }, components } }),
    });
    return { providerId: body.messages?.[0]?.id ?? null };
  }

  async _email(to, subject, text) {
    const c = this.cfg.email;
    const body = await this._json('https://api.resend.com/emails', {
      method: 'POST', headers: { authorization: `Bearer ${c.apiKey}`, 'content-type': 'application/json' }, body: JSON.stringify({ from: c.from, to: [to], subject, text }),
    });
    return { providerId: body.id ?? null };
  }
}
