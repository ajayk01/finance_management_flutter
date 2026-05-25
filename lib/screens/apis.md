# API Endpoints Documentation

> **Base URL:** `/api`  
> **Framework:** Next.js App Router (Route Handlers)

---

## Table of Contents

| # | Endpoint | Methods |
|---|----------|---------|
| 1 | [/api/accounts](#1-accounts) | GET, POST |
| 2 | [/api/add-expense](#2-add-expense) | POST, PUT |
| 3 | [/api/add-income](#3-add-income) | POST, PUT |
| 4 | [/api/add-investment](#4-add-investment) | POST, PUT |
| 5 | [/api/add-transfer](#5-add-transfer) | POST |
| 6 | [/api/all-transactions](#6-all-transactions) | GET, POST, DELETE |
| 7 | [/api/bank-details](#7-bank-details) | GET |
| 8 | [/api/bank-transactions](#8-bank-transactions) | GET |
| 9 | [/api/calculate-xirr](#9-calculate-xirr) | POST |
| 10 | [/api/categories](#10-categories) | GET, POST |
| 11 | [/api/categories/subcategory](#11-categoriessubcategory) | POST |
| 12 | [/api/credit-card-caps](#12-credit-card-caps) | GET, POST |
| 13 | [/api/credit-card-details](#13-credit-card-details) | GET |
| 14 | [/api/credit-card-transactions](#14-credit-card-transactions) | GET |
| 15 | [/api/financial-details](#15-financial-details) | GET |
| 16 | [/api/friend-transactions](#16-friend-transactions) | GET |
| 17 | [/api/friends-balance](#17-friends-balance) | GET |
| 18 | [/api/investment-accounts](#18-investment-accounts) | GET |
| 19 | [/api/mf-nav-data](#19-mf-nav-data) | GET |
| 20 | [/api/mf-portfolio-analysis](#20-mf-portfolio-analysis) | POST |
| 21 | [/api/monthly-expenses](#21-monthly-expenses) | GET |
| 22 | [/api/monthly-income](#22-monthly-income) | GET |
| 23 | [/api/monthly-investments](#23-monthly-investments) | GET |
| 24 | [/api/pay-cc-bill](#24-pay-cc-bill) | POST |
| 25 | [/api/settle-up](#25-settle-up) | POST |
| 26 | [/api/splitwise](#26-splitwise) | GET |
| 27 | [/api/splitwise-sync](#27-splitwise-sync) | GET |
| 28 | [/api/total-investments](#28-total-investments) | GET |
| 29 | [/api/unaudited-expenses](#29-unaudited-expenses) | GET, PUT, DELETE |
| 30 | [/api/unsettled-splitwise-expenses](#30-unsettled-splitwise-expenses) | GET |
| 31 | [/api/yearly-summary](#31-yearly-summary) | GET |

---

## 1. Accounts

`/api/accounts`

### GET — Fetch all accounts or filter by type

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `type` | `'bank' \| 'credit-card' \| 'investment' \| 'all'` | No | Filter accounts by type |

**Response:**

```json
{
  "bankAccounts": [{ "id": "", "name": "", "currentBalance": 0, "initialBalance": 0, "isActive": true, "logo": "" }],
  "creditCardAccounts": [{ "id": "", "name": "", "usedAmount": 0, "totalLimit": 0, "availableCredit": 0, "rewardPoints": 0 }],
  "investmentAccounts": [{ "id": "", "name": "", "totalInvested": 0, "totalWithdraw": 0, "currentValue": 0, "xirr": 0 }]
}
```

### POST — Create a new account

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountName` | string | Yes | Name of the account |
| `accountType` | `'Bank' \| 'Credit Card' \| 'Investment'` | Yes | Type of account |
| `initialBalance` | number | No | Initial balance (default: 0) |
| `totalLimit` | number | Yes (Credit Card) | Credit limit for credit cards |

**Response:**

```json
{ "success": true, "message": "Account created", "accountId": "" }
```

---

## 2. Add Expense

`/api/add-expense`

### POST — Create an expense transaction

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `amount` | number | Yes | Expense amount |
| `charges` | number | No | Additional charges (default: 0) |
| `date` | string (ISO) | Yes | Transaction date |
| `description` | string | No | Description |
| `account` | `{ id: string, type: 'Bank' \| 'Credit Card' }` | Yes | Account to debit |
| `categoryId` | string | No | Category ID |
| `subCategoryId` | string | No | Sub-category ID |
| `capId` | string | No | Credit card rewards cap ID |
| `includeSplitwise` | boolean | No | Include in Splitwise |
| `splitwiseGroupId` | string | No | Splitwise group ID |
| `splitwiseUserIds` | string[] | No | Splitwise user IDs to split with |
| `splitType` | `'equal' \| 'custom'` | No | How to split the expense |
| `customAmounts` | `Record<string, number>` | No | Custom split amounts per user |

**Response:**

```json
{ "success": true, "message": "", "transactionId": "", "splitwiseTransactionId": "" }
```

### PUT — Update an expense transaction

**Request Body:** Same as POST with additional `id` field.

**Response:**

```json
{ "success": true, "message": "" }
```

---

## 3. Add Income

`/api/add-income`

### POST — Create an income transaction

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `amount` | number | Yes | Income amount |
| `date` | string (ISO) | Yes | Transaction date |
| `description` | string | Yes | Description |
| `account` | `{ id: string, type: 'Bank' \| 'Credit Card' }` | Yes | Account to credit |
| `categoryId` | string | Yes | Category ID |
| `subCategoryId` | string | No | Sub-category ID |

**Response:**

```json
{ "success": true, "message": "", "transactionId": "" }
```

### PUT — Update an income transaction

**Request Body:** Same as POST with additional `id` and `accountId` fields.

**Response:**

```json
{ "success": true, "message": "" }
```

---

## 4. Add Investment

`/api/add-investment`

### POST — Create an investment transaction

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `amount` | number | Yes | Investment amount |
| `date` | string (ISO) | Yes | Transaction date |
| `description` | string | Yes | Description |
| `accountId` | string | Yes | Bank account ID (source) |
| `investmentAccountId` | string | Yes | Investment account ID (destination) |

**Response:**

```json
{ "success": true, "message": "", "transactionId": "" }
```

### PUT — Update an investment transaction

**Request Body:** Same as POST with additional `id` field.

**Response:**

```json
{ "success": true, "message": "" }
```

---

## 5. Add Transfer

`/api/add-transfer`

### POST — Transfer funds between accounts

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `fromAccountId` | number | Yes | Source account ID (positive) |
| `toAccountId` | number | Yes | Destination account ID (must differ from source) |
| `amount` | number | Yes | Transfer amount (positive) |
| `date` | string (ISO) | Yes | Transfer date |
| `description` | string | Yes | Description |

**Response:**

```json
{ "success": true, "message": "", "transactionId": "" }
```

---

## 6. All Transactions

`/api/all-transactions`

### GET — Fetch all transactions for a month/year

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `month` | string | Yes | Month (e.g., "01", "12") |
| `year` | string | Yes | Year (e.g., "2024") |

**Response:**

```json
{
  "transactions": [{
    "id": "", "date": "", "time": "", "description": "", "amount": 0,
    "type": "", "category": "", "subCategory": "", "accountId": "",
    "accountName": "", "categoryId": "", "subCategoryId": "",
    "investmentAccountId": "", "investmentAccountName": "",
    "splitwiseDetails": []
  }]
}
```

### POST — Bulk delete transactions

**Request Body:**

```json
{ "action": "bulk-delete", "transactionIds": ["id1", "id2"] }
```

**Response:**

```json
{ "success": true, "message": "" }
```

### DELETE — Delete a single transaction

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Transaction ID to delete |

**Response:**

```json
{ "success": true, "message": "" }
```

---

## 7. Bank Details

`/api/bank-details`

### GET — Fetch all active bank accounts

**Response:**

```json
{
  "bankAccounts": [{ "id": "", "name": "", "balance": 0, "initialBalance": 0, "logo": "" }]
}
```

---

## 8. Bank Transactions

`/api/bank-transactions`

### GET — Fetch transactions for a specific bank account

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `accountId` | string | Yes | Bank account ID |
| `month` | string | No | Month filter |
| `year` | string | No | Year filter |

**Response:**

```json
{ "transactions": [] }
```

---

## 9. Calculate XIRR

`/api/calculate-xirr`

### POST — Calculate XIRR for an investment account

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `investmentAccountId` | string | Yes | Investment account ID |

**Response:**

```json
{ "xirr": 12.5 }
```

---

## 10. Categories

`/api/categories`

### GET — Fetch all categories and subcategories

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `type` | `'expense' \| 'income' \| 'all'` | No | Filter by category type |

**Response:**

```json
{
  "categories": [{ "id": "", "name": "", "budget": 0, "type": "" }],
  "subCategories": [{ "id": "", "categoryId": "", "name": "", "budget": 0 }]
}
```

### POST — Create a new category

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `categoryName` | string | Yes | Category name |
| `categoryType` | `'expense' \| 'income'` | Yes | Category type |
| `budget` | number | No | Monthly budget (default: 0) |

**Response:**

```json
{ "id": "", "name": "", "budget": 0, "type": "" }
```

---

## 11. Categories/Subcategory

`/api/categories/subcategory`

### POST — Create a subcategory

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `categoryId` | number | Yes | Parent category ID |
| `subCategoryName` | string | Yes | Subcategory name |
| `budget` | number | No | Monthly budget (default: 0) |

**Response:**

```json
{ "id": "", "categoryId": "", "name": "", "budget": 0 }
```

---

## 12. Credit Card Caps

`/api/credit-card-caps`

### GET — Fetch credit card spending caps

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `creditCardId` | string | No | Filter by credit card |

**Response:**

```json
{
  "caps": [{
    "id": "", "creditCardId": "", "capName": "", "capTotalAmount": 0,
    "capPercentage": 0, "capCurrentAmount": 0, "remainingAmount": 0,
    "totalRewards": 0, "rewardPerAmount": 0
  }]
}
```

### POST — Create a new credit card cap

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `creditCardId` | string | Yes | Credit card ID |
| `capName` | string | Yes | Cap name |
| `capTotalAmount` | number | Yes | Total cap amount |
| `capPercentage` | number | Yes | Reward percentage |
| `rewardPerAmount` | number | No | Reward per spend unit (default: 100) |

**Response:**

```json
{ "success": true, "message": "", "capId": "" }
```

---

## 13. Credit Card Details

`/api/credit-card-details`

### GET — Fetch all active credit cards

**Response:**

```json
{
  "creditCardDetails": [{ "id": "", "name": "", "usedAmount": 0, "totalLimit": 0, "logo": "" }]
}
```

---

## 14. Credit Card Transactions

`/api/credit-card-transactions`

### GET — Fetch transactions for a specific credit card

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `creditCardId` | string | Yes | Credit card ID |
| `month` | string | No | Month filter |
| `year` | string | No | Year filter |

**Response:**

```json
{ "transactions": [] }
```

> Includes `rewards` field per transaction.

---

## 15. Financial Details

`/api/financial-details`

### GET — Fetch grouped monthly financial summary

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `month` | string | Yes | Month |
| `year` | string | Yes | Year |

**Response:**

```json
{
  "monthlyExpenses": [{ "year": "", "month": "", "category": "", "subCategory": "", "expense": 0 }],
  "monthlyIncome": [{ "year": "", "month": "", "category": "", "subCategory": "", "expense": 0 }],
  "monthlyInvestments": [{ "year": "", "month": "", "category": "", "subCategory": "", "expense": 0 }]
}
```

---

## 16. Friend Transactions

`/api/friend-transactions`

### GET — Fetch Splitwise transactions for a friend

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `friendId` | string | Yes | Friend ID |
| `friendName` | string | No | Friend name |

**Response:**

```json
{
  "transactions": [{
    "id": "", "splitwiseId": "", "date": "", "description": "",
    "amount": 0, "totalAmount": 0, "category": "", "subCategory": "",
    "accountId": "", "friendId": ""
  }],
  "friendName": "", "friendId": "", "count": 0
}
```

---

## 17. Friends Balance

`/api/friends-balance`

### GET — Fetch Splitwise friends and their balances

> 15-minute response caching enabled.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `refresh` | `'true'` | No | Bypass cache |

**Response:**

```json
{
  "friends": [{ "name": "", "splitwiseAmount": 0, "notionAmount": 0, "friendId": "" }]
}
```

---

## 18. Investment Accounts

`/api/investment-accounts`

### GET — Fetch all active investment accounts

**Response:**

```json
[{ "id": "", "name": "" }]
```

---

## 19. MF NAV Data

`/api/mf-nav-data`

### GET — Fetch mutual fund NAV history or search schemes

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `schemeCode` | string | No | Scheme code for NAV data |
| `search` | string | No | Search term for scheme lookup |
| `period` | `'1m' \| '3m' \| '6m' \| '1y' \| '3y' \| '5y' \| 'all'` | No | NAV history period (default: `'1y'`) |

**Response (Search Mode):**

```json
{ "results": [{ "schemeCode": "", "schemeName": "" }] }
```

**Response (NAV Mode):**

```json
{ "fundName": "", "chartData": [], "selectedBase": 0, "niftyBase": 0 }
```

---

## 20. MF Portfolio Analysis

`/api/mf-portfolio-analysis`

### POST — Analyze mutual fund portfolio

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `transactions` | `UploadedTransaction[]` | Yes | Array of MF transactions |

Each transaction:

| Field | Type | Description |
|-------|------|-------------|
| `fundName` | string | Fund name |
| `type` | string | Buy/Sell |
| `units` | number | Number of units |
| `nav` | number | NAV at transaction |
| `amount` | number | Transaction amount |
| `date` | string | Transaction date |

**Response:** Portfolio analysis with NAV history and Nifty 50 performance comparison.

---

## 21. Monthly Expenses

`/api/monthly-expenses`

### GET — Fetch monthly expense summary

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `month` | string | Yes | Month |
| `year` | string | Yes | Year |

**Response:**

```json
{
  "monthlyExpenses": [],
  "rawTransactions": [],
  "categories": [],
  "subCategories": []
}
```

---

## 22. Monthly Income

`/api/monthly-income`

### GET — Fetch monthly income summary

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `month` | string | Yes | Month |
| `year` | string | Yes | Year |

**Response:**

```json
{
  "monthlyIncome": [],
  "rawTransactions": [],
  "categories": [],
  "subCategories": []
}
```

---

## 23. Monthly Investments

`/api/monthly-investments`

### GET — Fetch monthly investment summary

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `month` | string | Yes | Month |
| `year` | string | Yes | Year |

**Response:**

```json
{
  "monthlyInvestments": [],
  "rawTransactions": [],
  "investmentAccounts": []
}
```

---

## 24. Pay CC Bill

`/api/pay-cc-bill`

### POST — Process a credit card bill payment

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `creditCardId` | string | Yes | Credit card ID |
| `bankAccountId` | string | Yes | Bank account to pay from |
| `amount` | number | Yes | Payment amount (positive) |
| `date` | number | No | Payment date (epoch timestamp) |
| `description` | string | No | Description |

**Response:**

```json
{ "success": true, "message": "", "transactionId": "", "capsReset": true }
```

> Resets credit card spending caps on bill payment.

---

## 25. Settle Up

`/api/settle-up`

### POST — Settle Splitwise expenses with a friend

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `friendId` | string | Yes | Friend ID |
| `bankAccountId` | string | Yes | Bank account for settlement |
| `unsettledExpenses` | object[] | No | Unsettled transactions to include |
| `settledTransactionIds` | string[] | No | Already settled transaction IDs |
| `date` | number | No | Settlement date |
| `totalSettlementAmount` | number | Yes | Net settlement amount |

**Response:**

```json
{ "success": true, "message": "", "offsetEntries": [] }
```

> Creates a single settlement transaction for the total amount.

---

## 26. Splitwise

`/api/splitwise`

### GET — Fetch Splitwise groups with members

**Response:**

```json
{
  "groups": [{
    "id": "", "name": "",
    "members": [{ "id": "", "friendId": "", "name": "" }]
  }]
}
```

---

## 27. Splitwise Sync

`/api/splitwise-sync`

### GET — Sync Splitwise notifications

Filters notifications from other users, fetches expense details, and creates corresponding expense records.

**Response:** Processed notifications and updated sync timestamp.

---

## 28. Total Investments

`/api/total-investments`

### GET — Fetch total investments across all accounts

**Response:**

```json
{
  "rawTransactions": [{ "id": "", "amount": 0, "type": "", "category": "", "description": "", "subCategory": "", "date": "" }],
  "investmentAccounts": []
}
```

---

## 29. Unaudited Expenses

`/api/unaudited-expenses`

### GET — Fetch expenses without categories

**Response:**

```json
{ "transactions": [] }
```

### PUT — Bulk update unaudited expenses with categories

**Request Body:**

```json
{
  "updates": [{ "id": "", "categoryId": "", "subCategoryId": "", "description": "" }]
}
```

**Response:**

```json
{ "success": true, "updatedIds": [] }
```

### DELETE — Delete unaudited expenses

**Request Body:**

```json
{ "ids": ["id1", "id2"] }
```

**Response:**

```json
{ "success": true, "deletedIds": [] }
```

---

## 30. Unsettled Splitwise Expenses

`/api/unsettled-splitwise-expenses`

### GET — Fetch unsettled Splitwise expenses for a friend

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `friendId` | string | Yes | Friend ID |

**Response:**

```json
{
  "success": true,
  "expenses": [{
    "splitwiseTransactionId": "", "friendId": "", "friendName": "",
    "date": "", "description": "", "splitedAmount": 0, "totalAmount": 0,
    "categoryId": "", "subCategoryId": ""
  }],
  "count": 0
}
```

---

## 31. Yearly Summary

`/api/yearly-summary`

### GET — Fetch yearly financial summary

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `year` | string | Yes | Year (2000–2100) |

**Response:**

```json
{
  "summaryData": [
    { "month": "Jan", "expense": 5000, "income": 50000, "investment": 10000 },
    { "month": "Feb", "expense": 4500, "income": 50000, "investment": 12000 }
  ]
}
```
