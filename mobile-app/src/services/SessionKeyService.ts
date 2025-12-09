/**
 * Session Key Service - ERC-4337 Account Abstraction
 *
 * Permite ejecutar swaps sin firmar cada transacción.
 * El usuario autoriza una "Session Key" con límites de gasto,
 * y el backend puede ejecutar operaciones dentro de esos límites.
 */

import { ethers } from 'ethers';

// Session Key configuration
export interface SessionKeyConfig {
  // The temporary key that can execute transactions
  sessionPublicKey: string;
  sessionPrivateKey: string; // Stored securely on device

  // Permissions and limits
  permissions: SessionPermissions;

  // Validity
  createdAt: number;
  expiresAt: number;
  isActive: boolean;
}

export interface SessionPermissions {
  // Maximum amount per transaction (in USD)
  maxAmountPerTx: number;

  // Maximum total amount during session (in USD)
  maxTotalAmount: number;

  // Amount already spent in this session
  amountSpent: number;

  // Allowed operations
  allowedActions: ('swap' | 'quote' | 'transfer')[];

  // Allowed token addresses (empty = all tokens)
  allowedTokens: string[];

  // Allowed recipient addresses (empty = only user's address)
  allowedRecipients: string[];
}

// Smart Account interface (ERC-4337 compatible)
export interface SmartAccount {
  address: string;
  owner: string;
  isDeployed: boolean;
  entryPoint: string;
}

// User Operation for ERC-4337
export interface UserOperation {
  sender: string;
  nonce: string;
  initCode: string;
  callData: string;
  callGasLimit: string;
  verificationGasLimit: string;
  preVerificationGas: string;
  maxFeePerGas: string;
  maxPriorityFeePerGas: string;
  paymasterAndData: string;
  signature: string;
}

/**
 * SessionKeyService - Manages session keys for gasless, signature-less swaps
 */
class SessionKeyService {
  private currentSession: SessionKeyConfig | null = null;
  private smartAccount: SmartAccount | null = null;

  // Default session duration: 2 hours
  private readonly DEFAULT_DURATION_MS = 2 * 60 * 60 * 1000;

  // Default limits
  private readonly DEFAULT_MAX_PER_TX = 100; // $100 USD
  private readonly DEFAULT_MAX_TOTAL = 500; // $500 USD per session

  /**
   * Initialize the service with user's main wallet
   */
  async initialize(userWalletAddress: string): Promise<void> {
    // In production, this would:
    // 1. Check if user has a Smart Account deployed
    // 2. Deploy one if needed (using a factory contract)
    // 3. Store the smart account details

    this.smartAccount = {
      address: userWalletAddress, // In production, this would be the Smart Account address
      owner: userWalletAddress,
      isDeployed: true,
      entryPoint: '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789', // ERC-4337 EntryPoint
    };

    console.log('[SessionKeyService] Initialized for wallet:', userWalletAddress);
  }

  /**
   * Create a new session key
   * This requires user's biometric/PIN confirmation ONCE
   */
  async createSession(
    options: {
      durationMs?: number;
      maxAmountPerTx?: number;
      maxTotalAmount?: number;
      allowedTokens?: string[];
    } = {}
  ): Promise<SessionKeyConfig> {
    // Generate a new ephemeral key pair
    const sessionWallet = ethers.Wallet.createRandom();

    const now = Date.now();
    const session: SessionKeyConfig = {
      sessionPublicKey: sessionWallet.address,
      sessionPrivateKey: sessionWallet.privateKey,

      permissions: {
        maxAmountPerTx: options.maxAmountPerTx || this.DEFAULT_MAX_PER_TX,
        maxTotalAmount: options.maxTotalAmount || this.DEFAULT_MAX_TOTAL,
        amountSpent: 0,
        allowedActions: ['swap', 'quote'],
        allowedTokens: options.allowedTokens || [],
        allowedRecipients: this.smartAccount ? [this.smartAccount.owner] : [],
      },

      createdAt: now,
      expiresAt: now + (options.durationMs || this.DEFAULT_DURATION_MS),
      isActive: true,
    };

    // In production, this would:
    // 1. Request user's signature (FaceID/TouchID) to authorize the session key
    // 2. Register the session key on-chain or with a session key module
    // 3. Store securely in device keychain

    this.currentSession = session;

    console.log('[SessionKeyService] Session created:', {
      publicKey: session.sessionPublicKey,
      expiresAt: new Date(session.expiresAt).toISOString(),
      maxPerTx: session.permissions.maxAmountPerTx,
      maxTotal: session.permissions.maxTotalAmount,
    });

    return session;
  }

  /**
   * Check if we have a valid session
   */
  hasValidSession(): boolean {
    if (!this.currentSession) return false;
    if (!this.currentSession.isActive) return false;
    if (Date.now() > this.currentSession.expiresAt) return false;

    return true;
  }

  /**
   * Get remaining session allowance
   */
  getRemainingAllowance(): { perTx: number; total: number } {
    if (!this.currentSession) {
      return { perTx: 0, total: 0 };
    }

    const remaining =
      this.currentSession.permissions.maxTotalAmount -
      this.currentSession.permissions.amountSpent;

    return {
      perTx: Math.min(this.currentSession.permissions.maxAmountPerTx, remaining),
      total: remaining,
    };
  }

  /**
   * Check if an operation is allowed under current session
   */
  canExecute(amountUSD: number, action: 'swap' | 'quote' | 'transfer'): {
    allowed: boolean;
    reason?: string;
  } {
    if (!this.hasValidSession()) {
      return { allowed: false, reason: 'No valid session. Please authorize a new session.' };
    }

    const session = this.currentSession!;

    // Check action is allowed
    if (!session.permissions.allowedActions.includes(action)) {
      return { allowed: false, reason: `Action '${action}' not allowed in this session.` };
    }

    // Check per-transaction limit
    if (amountUSD > session.permissions.maxAmountPerTx) {
      return {
        allowed: false,
        reason: `Amount exceeds per-transaction limit of $${session.permissions.maxAmountPerTx}.`,
      };
    }

    // Check total session limit
    const remaining =
      session.permissions.maxTotalAmount - session.permissions.amountSpent;
    if (amountUSD > remaining) {
      return {
        allowed: false,
        reason: `Amount exceeds remaining session limit of $${remaining.toFixed(2)}.`,
      };
    }

    return { allowed: true };
  }

  /**
   * Sign a user operation with the session key
   */
  async signUserOperation(
    callData: string,
    amountUSD: number
  ): Promise<{ signature: string; userOp: Partial<UserOperation> }> {
    if (!this.currentSession || !this.smartAccount) {
      throw new Error('No active session');
    }

    // Verify the operation is allowed
    const canExec = this.canExecute(amountUSD, 'swap');
    if (!canExec.allowed) {
      throw new Error(canExec.reason);
    }

    // Create the session key wallet
    const sessionWallet = new ethers.Wallet(this.currentSession.sessionPrivateKey);

    // Build user operation
    const userOp: Partial<UserOperation> = {
      sender: this.smartAccount.address,
      callData,
      // Other fields would be filled by the bundler service
    };

    // Sign the user operation hash with session key
    const userOpHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'bytes'],
        [userOp.sender, userOp.callData]
      )
    );

    const signature = await sessionWallet.signMessage(ethers.utils.arrayify(userOpHash));

    // Update spent amount
    this.currentSession.permissions.amountSpent += amountUSD;

    console.log('[SessionKeyService] Signed operation:', {
      amountUSD,
      totalSpent: this.currentSession.permissions.amountSpent,
      remaining: this.getRemainingAllowance().total,
    });

    return { signature, userOp };
  }

  /**
   * Revoke current session
   */
  revokeSession(): void {
    if (this.currentSession) {
      this.currentSession.isActive = false;
      console.log('[SessionKeyService] Session revoked');
    }
    this.currentSession = null;
  }

  /**
   * Get session info for display
   */
  getSessionInfo(): {
    active: boolean;
    expiresIn?: string;
    remaining?: { perTx: number; total: number };
  } {
    if (!this.hasValidSession()) {
      return { active: false };
    }

    const session = this.currentSession!;
    const expiresInMs = session.expiresAt - Date.now();
    const expiresInMinutes = Math.floor(expiresInMs / 60000);

    return {
      active: true,
      expiresIn:
        expiresInMinutes > 60
          ? `${Math.floor(expiresInMinutes / 60)}h ${expiresInMinutes % 60}m`
          : `${expiresInMinutes}m`,
      remaining: this.getRemainingAllowance(),
    };
  }
}

// Export singleton
export const sessionKeyService = new SessionKeyService();

export default SessionKeyService;
