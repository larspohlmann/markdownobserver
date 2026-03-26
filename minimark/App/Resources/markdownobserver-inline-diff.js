function tokenizeDiffText(textValue) {
  var text = String(textValue || "");
  if (text.length === 0) {
    return [];
  }

  return text.match(/(\s+|[A-Za-z0-9_]+|[^\sA-Za-z0-9_])/g) || [];
}

function buildLCSMatrix(previousTokens, currentTokens) {
  var rows = previousTokens.length + 1;
  var cols = currentTokens.length + 1;
  var matrix = new Array(rows);

  for (var row = 0; row < rows; row += 1) {
    matrix[row] = new Array(cols);
    for (var col = 0; col < cols; col += 1) {
      matrix[row][col] = 0;
    }
  }

  for (var i = previousTokens.length - 1; i >= 0; i -= 1) {
    for (var j = currentTokens.length - 1; j >= 0; j -= 1) {
      if (previousTokens[i] === currentTokens[j]) {
        matrix[i][j] = matrix[i + 1][j + 1] + 1;
      } else {
        matrix[i][j] = Math.max(matrix[i + 1][j], matrix[i][j + 1]);
      }
    }
  }

  return matrix;
}

function buildTokenDiffOperations(previousTokens, currentTokens, matrix) {
  var operations = [];
  var i = 0;
  var j = 0;

  while (i < previousTokens.length && j < currentTokens.length) {
    if (previousTokens[i] === currentTokens[j]) {
      operations.push({
        type: "equal",
        previousIndex: i,
        currentIndex: j
      });
      i += 1;
      j += 1;
      continue;
    }

    if (matrix[i + 1][j] > matrix[i][j + 1]) {
      operations.push({
        type: "delete",
        previousIndex: i,
        currentIndex: null
      });
      i += 1;
      continue;
    }

    if (matrix[i + 1][j] < matrix[i][j + 1]) {
      operations.push({
        type: "insert",
        previousIndex: null,
        currentIndex: j
      });
      j += 1;
      continue;
    }

    operations.push({
      type: "insert",
      previousIndex: null,
      currentIndex: j
    });
    j += 1;
  }

  while (i < previousTokens.length) {
    operations.push({
      type: "delete",
      previousIndex: i,
      currentIndex: null
    });
    i += 1;
  }

  while (j < currentTokens.length) {
    operations.push({
      type: "insert",
      previousIndex: null,
      currentIndex: j
    });
    j += 1;
  }

  return operations;
}

function buildRemovedTokenMask(previousText, currentText) {
  var previousTokens = tokenizeDiffText(previousText);
  var currentTokens = tokenizeDiffText(currentText);
  var matrix = buildLCSMatrix(previousTokens, currentTokens);
  var operations = buildTokenDiffOperations(previousTokens, currentTokens, matrix);
  var removedKinds = new Array(previousTokens.length);

  for (var maskIndex = 0; maskIndex < removedKinds.length; maskIndex += 1) {
    removedKinds[maskIndex] = null;
  }

  var pendingDeletedIndexes = [];
  var pendingNonWhitespaceInsertCount = 0;

  function flushPendingSegment() {
    if (pendingDeletedIndexes.length === 0) {
      pendingNonWhitespaceInsertCount = 0;
      return;
    }

    var removalKind = pendingNonWhitespaceInsertCount > 0 ? "edited" : "deleted";
    for (var pendingIndex = 0; pendingIndex < pendingDeletedIndexes.length; pendingIndex += 1) {
      removedKinds[pendingDeletedIndexes[pendingIndex]] = removalKind;
    }
    pendingDeletedIndexes = [];
    pendingNonWhitespaceInsertCount = 0;
  }

  for (var operationIndex = 0; operationIndex < operations.length; operationIndex += 1) {
    var operation = operations[operationIndex];

    if (operation.type === "equal") {
      flushPendingSegment();
      continue;
    }

    if (operation.type === "delete") {
      pendingDeletedIndexes.push(operation.previousIndex);
      continue;
    }

    if (operation.type === "insert") {
      var insertedToken = currentTokens[operation.currentIndex];
      if (!/^\s+$/.test(String(insertedToken || ""))) {
        pendingNonWhitespaceInsertCount += 1;
      }
    }
  }

  flushPendingSegment();

  return {
    tokens: previousTokens,
    removedKinds: removedKinds
  };
}

function applyInlineDiffRemovedStyle(element, removedKind) {
  if (!element || !element.style) {
    return;
  }

  if (removedKind === "deleted") {
    element.style.backgroundColor = "var(--reader-changed-deleted)";
    element.style.background = "var(--reader-changed-deleted)";
    return;
  }

  element.style.backgroundColor = "var(--reader-changed-edited)";
  element.style.background = "color-mix(in srgb, var(--reader-changed-edited) 28%, transparent)";
}
