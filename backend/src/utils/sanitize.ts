const CONTROL_CHARS_REGEX = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const sanitizeText = (value: unknown): string | null => {
  if (value === null || value === undefined) {
    return null;
  }

  const text = String(value).replace(CONTROL_CHARS_REGEX, '').trim();

  if (!text) {
    return null;
  }

  return text;
};

export const sanitizeDisplayName = (value: unknown): string => {
  const sanitized = sanitizeText(value);

  if (!sanitized) {
    return 'مستخدم';
  }

  if (EMAIL_REGEX.test(sanitized)) {
    return 'مستخدم';
  }

  return sanitized;
};

const joinNames = (first?: unknown, last?: unknown): string | null => {
  const sanitizedFirst = sanitizeText(first);
  const sanitizedLast = sanitizeText(last);

  if (!sanitizedFirst && !sanitizedLast) {
    return null;
  }

  if (sanitizedFirst && sanitizedLast) {
    return `${sanitizedFirst} ${sanitizedLast}`.trim();
  }

  return sanitizedFirst ?? sanitizedLast;
};

const extractCandidates = (candidate: unknown): string[] => {
  if (candidate === null || candidate === undefined) {
    return [];
  }

  if (typeof candidate === 'string') {
    return [candidate];
  }

  if (typeof candidate === 'object' && !Array.isArray(candidate)) {
    const record = candidate as Record<string, unknown>;
    const values: Array<unknown> = [
      record.displayName,
      record.fullName,
      record.name,
      record.username,
      joinNames(record.firstName, record.lastName),
    ];

    const nested: string[] = [];
    for (const value of values) {
      nested.push(...extractCandidates(value));
    }
    return nested;
  }

  return [String(candidate)];
};

export const selectDisplayName = (
  ...candidates: Array<unknown | undefined>
): string => {
  for (const candidate of candidates) {
    const extracted = extractCandidates(candidate);
    for (const value of extracted) {
      const sanitized = sanitizeDisplayName(value);
      if (sanitized !== 'مستخدم') {
        return sanitized;
      }
    }
  }

  return 'مستخدم';
};
