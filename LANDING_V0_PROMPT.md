# VoiceSwap Landing Page - V0 Prompt

---

## 🎯 Main Prompt for V0

```
Create a modern, sleek landing page for "VoiceSwap" - a voice-activated crypto swap app for Meta Ray-Ban smart glasses.

STYLE REFERENCE: Meta AI Glasses landing page aesthetic (clean, futuristic, product-focused)
- Hero section with gradient backgrounds (deep purple to blue)
- Large, bold typography with plenty of white space
- Smooth scroll animations
- Product showcase with floating/3D elements
- Dark theme with accent colors
- Mobile-first responsive design

COLOR PALETTE:
- Primary: Deep Purple (#6B46C1) to Electric Blue (#3B82F6) gradient
- Secondary: Bright Cyan (#06B6D4)
- Accent: Neon Green (#10B981) for CTAs
- Background: Dark slate (#0F172A)
- Text: White (#FFFFFF) and Light Gray (#E2E8F0)

SECTIONS TO INCLUDE:

1. HERO SECTION
   - Headline: "Swap Crypto With Your Voice"
   - Subheadline: "The future of DeFi is hands-free. Trade tokens instantly using Meta Ray-Ban smart glasses."
   - CTA Button: "Join Waitlist" (neon green)
   - Background: Animated gradient mesh
   - Floating visual: Meta Ray-Ban glasses mockup with holographic swap interface

2. HOW IT WORKS (3-step process with icons)
   Step 1: "Speak Your Intent"
   - Icon: Voice waveform
   - Description: "Just say: 'Swap 10 USDC to ETH'"

   Step 2: "AI Understands & Executes"
   - Icon: Brain/AI chip
   - Description: "Advanced AI parses your command in Spanish or English"

   Step 3: "Instant Confirmation"
   - Icon: Checkmark with sparkles
   - Description: "Gas-free swap executed in seconds. See results in your glasses."

3. KEY FEATURES (Grid layout with cards)
   Feature 1: "Zero Gas Fees"
   - Icon: Fire crossed out
   - Description: "All transactions sponsored via Account Abstraction"

   Feature 2: "Voice-First Design"
   - Icon: Microphone
   - Description: "Control everything hands-free while on the go"

   Feature 3: "Multi-Language Support"
   - Icon: Globe with headphones
   - Description: "Works in English and Spanish natively"

   Feature 4: "Instant Execution"
   - Icon: Lightning bolt
   - Description: "Powered by Uniswap V4 on Unichain for maximum speed"

   Feature 5: "Secure Smart Wallets"
   - Icon: Shield with lock
   - Description: "Session keys protect your funds with granular permissions"

   Feature 6: "Real-Time Updates"
   - Icon: Bell notification
   - Description: "See swap status projected in your Ray-Ban display"

4. PRODUCT SHOWCASE (Alternating left-right layout)
   Scene 1: "Hands-Free Trading"
   - Image: Person wearing Ray-Bans, walking in city
   - Caption: "Trade while commuting, exercising, or working"

   Scene 2: "AI-Powered Intelligence"
   - Image: Holographic interface showing swap confirmation
   - Caption: "Thirdweb AI understands natural language commands"

   Scene 3: "Your Crypto, Your Way"
   - Image: Balance display in AR overlay
   - Caption: "Check balances, history, and swap status instantly"

5. TECHNICAL SPECS (Minimalist cards)
   - "Built on Unichain" (Uniswap logo)
   - "Powered by Thirdweb" (Thirdweb logo)
   - "ERC-4337 Account Abstraction"
   - "x402 Micropayments"
   - "Meta Wearables SDK"

6. WAITLIST SECTION
   - Headline: "Be Among The First"
   - Subheadline: "VoiceSwap launches Q1 2025. Reserve your spot now."
   - Email input field (floating label style)
   - CTA: "Join Waitlist"
   - Small text: "No spam. Early access for first 1000 users."

7. FAQ SECTION (Accordion style)
   Q1: "Do I need Meta Ray-Ban glasses?"
   A: "Yes, VoiceSwap is designed exclusively for Meta Ray-Ban smart glasses with built-in audio and camera."

   Q2: "What tokens can I swap?"
   A: "Currently supports WETH, USDC, and all major tokens on Unichain. More chains coming soon."

   Q3: "How much does it cost?"
   A: "All gas fees are sponsored. We charge a small micropayment (x402) of $0.02 per swap."

   Q4: "Is my wallet secure?"
   A: "Yes. VoiceSwap uses ERC-4337 smart wallets with session keys, limiting permissions and protecting your funds."

   Q5: "When does it launch?"
   A: "Public launch scheduled for Q1 2025. Join waitlist for early access."

8. FOOTER
   - Logo: VoiceSwap
   - Tagline: "The Voice of DeFi"
   - Links: About | Privacy | Terms | Twitter | GitHub
   - Legal: "© 2025 VoiceSwap. Not affiliated with Meta Platforms, Inc."

ANIMATIONS TO INCLUDE:
- Hero gradient mesh should subtly shift colors
- Floating Ray-Ban glasses should slowly rotate in 3D
- Feature cards should fade in on scroll
- Numbers/stats should count up when visible
- CTA buttons should have glow effect on hover

TYPOGRAPHY:
- Headings: Inter or SF Pro Display (bold, 64px hero, 48px sections)
- Body: Inter or SF Pro Text (regular, 18px)
- Monospace for addresses/technical data

COMPONENTS TO USE:
- Glassmorphism cards (frosted glass effect)
- Gradient borders on feature cards
- Floating shadows (multi-layer)
- Smooth scroll snap
- Parallax effects on product images

MOBILE OPTIMIZATIONS:
- Stack sections vertically
- Reduce hero text to 36px
- Touch-friendly button sizes (min 44px)
- Swipeable feature carousel

ACCESSIBILITY:
- ARIA labels for all interactive elements
- Focus states with visible outlines
- Sufficient color contrast (WCAG AA)
- Keyboard navigation support

CODE PREFERENCES:
- Use Next.js 14 with App Router
- Tailwind CSS for styling
- Framer Motion for animations
- shadcn/ui components
- TypeScript
```

---

## 📸 Visual Reference Points

### Hero Section Inspiration
```
Imagine:
- Large 3D rendering of Meta Ray-Ban glasses floating in space
- Holographic swap interface projected from the glasses
- Particle effects around the glasses (like digital dust)
- Gradient background: deep purple → electric blue
- Headline overlaid in bold white text
```

### Feature Cards Style
```
Card Design:
┌─────────────────────────────┐
│  [Icon: 64px, cyan color]   │
│                             │
│  Feature Title              │
│  (Bold, 24px, white)        │
│                             │
│  Description text here      │
│  (Regular, 16px, gray-300)  │
│                             │
│  [Learn more →]             │
└─────────────────────────────┘

Background: rgba(255,255,255,0.05)
Border: 1px solid rgba(255,255,255,0.1)
Border-radius: 24px
Backdrop-filter: blur(10px)
```

### How It Works Flow
```
[1] ──────────> [2] ──────────> [3]

Voice Input     AI Processing   Confirmation
🎤              🧠              ✅

Connected with animated gradient line
Numbers in gradient circles
Icons with subtle glow effect
```

---

## 🎨 Additional Design Details

### Gradient Specifications
```css
/* Hero Background */
background: linear-gradient(135deg,
  #6B46C1 0%,    /* Deep Purple */
  #4338CA 50%,   /* Indigo */
  #3B82F6 100%   /* Electric Blue */
);

/* CTA Button */
background: linear-gradient(90deg,
  #10B981 0%,    /* Neon Green */
  #06B6D4 100%   /* Bright Cyan */
);

/* Card Borders */
border-image: linear-gradient(90deg,
  rgba(59, 130, 246, 0.5),
  rgba(16, 185, 129, 0.5)
) 1;
```

### Typography Scale
```
Hero Headline: 64px / Bold / Line-height: 1.1
Hero Subheadline: 24px / Regular / Line-height: 1.5
Section Titles: 48px / Bold / Line-height: 1.2
Feature Titles: 24px / Semibold / Line-height: 1.3
Body Text: 18px / Regular / Line-height: 1.6
Button Text: 16px / Medium / Letter-spacing: 0.5px
```

### Spacing System
```
Sections: 120px vertical padding
Cards: 32px padding
Grid gap: 24px
Button padding: 16px 32px
```

---

## 🚀 Interactive Elements

### Waitlist Form
```tsx
<form className="flex flex-col gap-4 max-w-md mx-auto">
  <div className="relative">
    <input
      type="email"
      placeholder="your@email.com"
      className="w-full px-6 py-4 rounded-full bg-white/5 border border-white/10 text-white placeholder-gray-400 focus:border-cyan-400 focus:ring-2 focus:ring-cyan-400/20"
    />
  </div>
  <button className="px-8 py-4 rounded-full bg-gradient-to-r from-green-500 to-cyan-400 text-white font-medium hover:scale-105 transition-transform">
    Join Waitlist
  </button>
  <p className="text-sm text-gray-400 text-center">
    🔒 No spam. Early access for first 1,000 users.
  </p>
</form>
```

### Stat Counter Animation
```tsx
<div className="grid grid-cols-3 gap-8 text-center">
  <div>
    <div className="text-5xl font-bold text-cyan-400">
      <CountUp end={1000} duration={2} suffix="+" />
    </div>
    <div className="text-gray-400 mt-2">Waitlist Members</div>
  </div>
  <div>
    <div className="text-5xl font-bold text-green-400">
      <CountUp end={10000} duration={2} suffix="+" />
    </div>
    <div className="text-gray-400 mt-2">Swaps Executed</div>
  </div>
  <div>
    <div className="text-5xl font-bold text-purple-400">
      <CountUp end={0} duration={2} prefix="$" />
    </div>
    <div className="text-gray-400 mt-2">Gas Fees Paid</div>
  </div>
</div>
```

---

## 📱 Mobile-First Considerations

### Breakpoints
```
Mobile: 320px - 640px
Tablet: 640px - 1024px
Desktop: 1024px+

Mobile adjustments:
- Hero text: 36px → 24px
- Section padding: 120px → 60px
- Grid: 3 columns → 1 column
- Feature cards: Stack vertically
- Glasses 3D model: Smaller, less rotation
```

### Touch Interactions
```
- Swipeable feature carousel on mobile
- Pull-to-refresh on waitlist submission
- Haptic feedback on button press (if supported)
- Enlarged tap targets (min 44x44px)
```

---

## 🎬 Micro-interactions

### Button Hover States
```tsx
className="
  relative overflow-hidden
  before:absolute before:inset-0
  before:bg-gradient-to-r before:from-transparent before:via-white/20 before:to-transparent
  before:translate-x-[-200%] hover:before:translate-x-[200%]
  before:transition-transform before:duration-700
  transition-all duration-200
  hover:scale-105 hover:shadow-2xl hover:shadow-cyan-500/50
"
```

### Scroll Reveal
```tsx
// Fade in on scroll
<motion.div
  initial={{ opacity: 0, y: 50 }}
  whileInView={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.6 }}
  viewport={{ once: true }}
>
  {children}
</motion.div>
```

---

## 🔗 Legal & Disclaimers

**Important footer text:**
```
"VoiceSwap is an independent application and is not affiliated with,
endorsed by, or sponsored by Meta Platforms, Inc. Meta Ray-Ban is a
trademark of Meta Platforms, Inc. Use of VoiceSwap requires compatible
Meta Ray-Ban smart glasses (sold separately)."
```

---

## ✅ V0 Generation Checklist

When generating in V0:
- [ ] Start with "Create a landing page for VoiceSwap..."
- [ ] Specify dark theme with purple-blue gradient
- [ ] Request hero section with 3D product mockup
- [ ] Include 6 feature cards in grid
- [ ] Add 3-step "How It Works" flow
- [ ] Include waitlist email form
- [ ] Add FAQ accordion section
- [ ] Request Framer Motion animations
- [ ] Specify Tailwind + shadcn/ui
- [ ] Request mobile-responsive design

---

## 🎯 Final V0 Prompt (Copy-Paste Ready)

```
Create a modern, dark-themed landing page for "VoiceSwap" - a voice-activated crypto trading app for Meta Ray-Ban smart glasses.

HERO SECTION:
- Headline: "Swap Crypto With Your Voice"
- Subheadline: "The future of DeFi is hands-free. Trade tokens instantly using Meta Ray-Ban smart glasses."
- Gradient background: deep purple (#6B46C1) to electric blue (#3B82F6)
- Floating 3D Meta Ray-Ban glasses with holographic swap interface
- CTA button: "Join Waitlist" with neon green gradient
- Add subtle particle effects

HOW IT WORKS (3 steps):
1. "Speak Your Intent" - Voice waveform icon
2. "AI Understands & Executes" - Brain/chip icon
3. "Instant Confirmation" - Checkmark icon
Connect with animated gradient line, show flow left to right

KEY FEATURES (6 cards in grid):
- Zero Gas Fees (fire crossed out icon)
- Voice-First Design (microphone icon)
- Multi-Language Support (globe icon)
- Instant Execution (lightning icon)
- Secure Smart Wallets (shield icon)
- Real-Time Updates (bell icon)

Each card: glassmorphism style, gradient border, icon + title + description

WAITLIST SECTION:
- Email input with floating label
- "Join Waitlist" button (green-cyan gradient)
- Stats counter: "1000+ members" "10,000+ swaps" "$0 gas fees"

FAQ (accordion):
- Do I need Meta Ray-Ban glasses?
- What tokens can I swap?
- How much does it cost?
- Is my wallet secure?
- When does it launch?

FOOTER:
- Logo + tagline
- Links: About, Privacy, Terms, Twitter, GitHub
- Disclaimer: "© 2025 VoiceSwap. Not affiliated with Meta Platforms, Inc."

STYLING:
- Use Next.js 14, Tailwind CSS, Framer Motion, shadcn/ui
- Dark background (#0F172A)
- Glassmorphism cards with backdrop blur
- Smooth scroll animations (fade in on view)
- Gradient accents throughout
- Mobile-first responsive design
- Typography: Inter font family

ANIMATIONS:
- Hero gradient mesh subtle shift
- 3D glasses slow rotation
- Feature cards fade in on scroll
- Stats count up when visible
- Button glow on hover
```

---

**Este prompt está listo para copiar y pegar en V0!** 🚀
