// The logic of CSV export and import in the Kanban. Pure where it can be, so it is tested
// without a screen.

import { isFileEmpty } from 'shared/helpers/FileHelper';

// Mirrors Custom::Kanban::CsvFile.
export const MAX_BYTES = 2 * 1024 * 1024;
export const MAX_ROWS = 5000;

// What is wrong with a file before it is even sent, or null.
export const fileProblem = file => {
  if (!file) return 'none';
  if (!/\.(csv|txt)$/i.test(file.name) && !/csv|text\/plain/.test(file.type))
    return 'type';
  if (file.size > MAX_BYTES) return 'size';
  if (isFileEmpty(file)) return 'empty';
  return null;
};

// The name the server gave the download (Content-Disposition), or `fallback`.
export const filenameFrom = (disposition, fallback) => {
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition || '');
  if (!match) return fallback;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return match[1];
  }
};

// Hands a downloaded blob to the browser as a file.
export const saveBlob = (blob, name) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
};

// What will happen to a row, said three ways (tone, icon, word key).
const ACTION_VIEWS = {
  create: { tone: 'teal', icon: 'i-lucide-plus', key: 'CREATE' },
  update: { tone: 'blue', icon: 'i-lucide-pencil', key: 'UPDATE' },
  skip: { tone: 'slate', icon: 'i-lucide-minus', key: 'SKIP' },
  error: { tone: 'ruby', icon: 'i-lucide-x', key: 'ERROR' },
};

export const actionView = action => ACTION_VIEWS[action] || ACTION_VIEWS.skip;

// Rows that will be written when the import runs.
export const writableRows = payload => payload.created + payload.updated;

// An analysed import can run when its required columns are mapped and at least one row can be
// imported (rows with errors are left out and offered back as a file).
export const canRun = (payload, analysis) =>
  payload.status === 'analyzed' &&
  analysis.missing.length === 0 &&
  writableRows(payload) > 0;

export const isFinished = status => status === 'done' || status === 'failed';

// The rows a cell grid shows: the first `limit` cells of a row, so a wide file stays readable.
export const visibleCells = (cells, limit = 6) => cells.slice(0, limit);
