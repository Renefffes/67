import React, { useState, useEffect, useRef, useCallback } from "react";
import { User, CheckCircle2, ArrowRight, MapPin, Mail, Lock } from "lucide-react";

interface TypewriterLinesProps {
  lines: string[];
  trigger: boolean;
  onComplete: () => void;
}

const TypewriterLines: React.FC<TypewriterLinesProps> = ({ lines, trigger, onComplete }) => {
  const [displayedText, setDisplayedText] = useState<string[]>(["", "", ""]);
  const [currentLineIndex, setCurrentLineIndex] = useState<number>(0);
  const [currentCharIndex, setCurrentCharIndex] = useState<number>(0);

  // Reset typing state when trigger becomes false
  useEffect(() => {
    if (!trigger) {
      setDisplayedText(["", "", ""]);
      setCurrentLineIndex(0);
      setCurrentCharIndex(0);
    }
  }, [trigger]);

  // Handle typing sequence
  useEffect(() => {
    if (!trigger) return;
    if (currentLineIndex >= lines.length) {
      onComplete();
      return;
    }

    const currentTargetText = lines[currentLineIndex];
    if (currentCharIndex < currentTargetText.length) {
      const timer = setTimeout(() => {
        setDisplayedText((prev) => {
          const next = [...prev];
          next[currentLineIndex] = currentTargetText.slice(0, currentCharIndex + 1);
          return next;
        });
        setCurrentCharIndex((prev) => prev + 1);
      }, 25); // typing speed
      return () => clearTimeout(timer);
    } else {
      // Finished typing current line, pause and proceed to next line
      const timer = setTimeout(() => {
        setCurrentLineIndex((prev) => prev + 1);
        setCurrentCharIndex(0);
      }, 600); // delay before next line starts
      return () => clearTimeout(timer);
    }
  }, [trigger, currentLineIndex, currentCharIndex, lines, onComplete]);

  return (
    <div className="flex flex-col items-center gap-12 sm:gap-16 w-full max-w-2xl px-4">
      {lines.map((line, idx) => {
        const isCurrentlyTyping = trigger && currentLineIndex === idx;
        const textToDisplay = displayedText[idx];

        return (
          <div 
            key={idx} 
            className={`flex items-center justify-center w-full transition-all duration-700 ${
              textToDisplay || isCurrentlyTyping ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"
            }`}
          >
            <p className="text-white text-center text-xl sm:text-2xl md:text-3xl font-extrabold leading-snug font-sans tracking-tight drop-shadow-md min-h-[2.5em] max-w-xl">
              <span>{textToDisplay}</span>
              {isCurrentlyTyping && (
                <span className="inline-block ml-1 w-1 h-5 sm:h-7 bg-white/90 align-middle animate-pulse" />
              )}
            </p>
          </div>
        );
      })}
    </div>
  );
};

export default function App() {
  const [lang, setLang] = useState<"en" | "nl">("en");
  const [triggered, setTriggered] = useState(false);
  const [typingFinished, setTypingFinished] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const descriptionRef = useRef<HTMLParagraphElement>(null);

  // Waitlist Form State
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [city, setCity] = useState("");
  const [formSubmitted, setFormSubmitted] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [queueNumber, setQueueNumber] = useState(384);
  const [emailError, setEmailError] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) {
      setEmailError(lang === "en" ? "Email is required" : "E-mailadres is verplicht");
      return;
    }
    if (!/\S+@\S+\.\S+/.test(email)) {
      setEmailError(lang === "en" ? "Please enter a valid email" : "Voer een geldig e-mailadres in");
      return;
    }
    setEmailError("");
    setIsSubmitting(true);
    
    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ name, email, city }),
      });
      
      const data = await response.json();
      
      if (response.ok && data.success) {
        setQueueNumber(data.queueNumber);
        setFormSubmitted(true);
      } else {
        setEmailError(data.error || (lang === "en" ? "An error occurred. Please try again." : "Er is een fout opgetreden. Probeer het opnieuw."));
      }
    } catch (err) {
      console.error("Waitlist error:", err);
      setEmailError(lang === "en" ? "Connection error. Please try again." : "Verbindingsfout. Probeer het opnieuw.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleTypewriterComplete = useCallback(() => {
    setTypingFinished(true);
  }, []);

  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const scrollTop = e.currentTarget.scrollTop;
    if (scrollTop > 10) {
      setScrolled(true);
    } else {
      setScrolled(false);
    }
  };

  useEffect(() => {
    if (!triggered) {
      setTypingFinished(false);
    }
  }, [triggered]);

  // Fully localized content for both English and Dutch languages
  const content = {
    en: {
      nav: ["Home", "FAQ", "Contact"],
      login: "Login",
      heading1: "Find hidden opportunities.",
      heading2: "Grow faster.",
      description: "Discover local businesses that don't have a website yet. Find untapped leads, reach out first, and help businesses build their online presence.",
      langBtn: "Nederlands",
      scrollDown: "Scroll Down",
      lines: [
        "Find local businesses that don't have an online presence yet.",
        "Generate cold-reach-out templates to win clients effortlessly.",
        "Help offline shops digitize and secure recurring service contracts."
      ],
      waitlistHeading: "Get Early Access",
      waitlistSub: "Be the first to find untapped leads in your region. Secure your spot now.",
      waitlistName: "Full Name",
      waitlistEmail: "Email Address",
      waitlistCity: "Target City / Region",
      waitlistBtn: "Join Waitlist",
      waitlistLoading: "Securing your spot...",
      waitlistSuccess: "You're on the list!",
      waitlistSuccessDesc: "Thank you for joining. We've reserved your spot. We'll notify you as soon as Blank.finder is available in your area.",
      waitlistQueue: "Your Queue Position:"
    },
    nl: {
      nav: ["Home", "FAQ", "Contact"],
      login: "Inloggen",
      heading1: "Vind verborgen kansen.",
      heading2: "Groei sneller.",
      description: "Ontdek lokale bedrijven die nog geen website hebben. Vind onontdekte leads, neem als eerste contact op en help bedrijven hun online aanwezigheid op te bouwen.",
      langBtn: "English",
      scrollDown: "Scroll Naar Beneden",
      lines: [
        "Vind lokale bedrijven die nog geen online aanwezigheid hebben.",
        "Genereer kant-en-klare berichten om moeiteloos klanten te winnen.",
        "Help offline winkels te digitaliseren en verdien maandelijks terugkerende inkomsten."
      ],
      waitlistHeading: "Krijg Vroegtijdige Toegang",
      waitlistSub: "Vind als eerste onontdekte leads in jouw regio. Beveilig nu je plek.",
      waitlistName: "Volledige Naam",
      waitlistEmail: "E-mailadres",
      waitlistCity: "Doelstad / Regio",
      waitlistBtn: "Aanmelden Wachtlijst",
      waitlistLoading: "Je plek beveiligen...",
      waitlistSuccess: "Je staat op de lijst!",
      waitlistSuccessDesc: "Bedankt voor je aanmelding. We hebben je plek gereserveerd. We laten het je weten zodra Blank.finder beschikbaar is in jouw regio.",
      waitlistQueue: "Jouw positie op de wachtlijst:"
    }
  };

  const t = content[lang];

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        // If the description element is NOT intersecting, it means it's out of view!
        // boundingClientRect.top < 0 confirms we scrolled down past it.
        if (!entry.isIntersecting && entry.boundingClientRect.top < 0) {
          setTriggered(true);
        } else if (entry.isIntersecting) {
          setTriggered(false);
        }
      },
      {
        threshold: 0,
      }
    );

    if (descriptionRef.current) {
      observer.observe(descriptionRef.current);
    }

    return () => {
      observer.disconnect();
    };
  }, []);

  return (
    <div className="relative w-screen h-screen overflow-hidden">
      {/* Dynamic Background Gradient (Fixed to viewports so it doesn't scroll with content) */}
      <div className="fixed inset-0 bg-gradient-to-b from-[#084be6] via-[#1180f4] to-[#5ccbfb] z-0 pointer-events-none" />

      {/* BRAND NEW MINIMALIST FLOATING HEADER (NO TOP BAR BACKGROUND/CAPSULE, BARE TABS) */}
      <header className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-6 md:px-12 py-6">
        {/* Top Left Brand: Blank.finder */}
        <div className="flex items-center cursor-pointer select-none">
          <span className="text-white font-black text-xl md:text-2xl tracking-tight">
            Blank.finder
          </span>
        </div>

        {/* Top Middle Tabs: Just raw text links with NO background behind them */}
        <nav className="hidden sm:flex items-center gap-6 md:gap-8 text-[13px] font-semibold text-white/80 tracking-wide">
          {t.nav.map((link) => (
            <a
              key={link}
              href={`#${link.toLowerCase()}`}
              className="hover:text-white hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer"
            >
              {link}
            </a>
          ))}
        </nav>

        {/* Top Right: Login Button (Disabled / Coming Soon) */}
        <div className="flex items-center">
          <button 
            disabled
            className="bg-white/80 text-black/50 text-[12px] font-bold py-2.5 px-5 rounded-2xl flex items-center gap-2 shadow-lg cursor-not-allowed select-none"
            title={lang === "en" ? "Coming Soon" : "Binnenkort beschikbaar"}
          >
            <User className="w-3.5 h-3.5 stroke-[2.5]" />
            <span>{t.login}</span>
            <span className="text-[9px] bg-black/10 px-1.5 py-0.5 rounded text-black/60 font-medium tracking-wide">
              {lang === "en" ? "Soon" : "Soon"}
            </span>
          </button>
        </div>
      </header>

      {/* Scrollable Container */}
      <div onScroll={handleScroll} className="absolute inset-0 overflow-y-auto overflow-x-hidden z-10 scroll-smooth select-text pb-0">
        
        {/* SECTION 1: HERO VIEW */}
        <section id="home" className="h-screen w-full flex flex-col items-center justify-center relative px-6 flex-shrink-0">
          <div className="flex flex-col items-center text-center max-w-4xl animate-fade-in mt-16 sm:mt-12">
            <h1 className="flex flex-col gap-1 sm:gap-2 leading-[1.05]">
              <span className="text-white text-5xl sm:text-6xl md:text-7xl lg:text-[84px] font-extrabold tracking-tight font-sans drop-shadow-sm">
                {t.heading1}
              </span>
              <span className="text-white text-5xl sm:text-6xl md:text-7xl lg:text-[84px] font-serif italic tracking-tight font-light drop-shadow-sm">
                {t.heading2}
              </span>
            </h1>

            <p ref={descriptionRef} className="mt-8 text-white/90 text-sm sm:text-base md:text-[17px] max-w-[620px] leading-relaxed font-sans font-medium tracking-wide drop-shadow-sm opacity-95">
              {t.description}
            </p>
          </div>

          {/* Scroll Down Indicator */}
          <div className="absolute bottom-10 flex flex-col items-center gap-1.5 opacity-60 animate-bounce text-white text-[11px] font-semibold tracking-wider uppercase select-none">
            <span>{t.scrollDown}</span>
            <svg className="w-4 h-4 stroke-[2.5]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
            </svg>
          </div>
        </section>

        {/* SECTION 2: SCROLL-TRIGGERED TYPEWRITER DETAILS */}
        <section id="details" className="h-screen w-full flex flex-col items-center justify-center relative px-6 flex-shrink-0">
          <TypewriterLines lines={t.lines} trigger={triggered} onComplete={handleTypewriterComplete} />
          
          {/* Scroll down to waitlist indicator */}
          {typingFinished && (
            <div className="absolute bottom-10 flex flex-col items-center gap-1.5 opacity-60 animate-bounce text-white text-[11px] font-semibold tracking-wider uppercase select-none animate-fade-in">
              <span>{lang === "en" ? "Join the Waitlist" : "Meld je aan voor de wachtlijst"}</span>
              <svg className="w-4 h-4 stroke-[2.5]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
              </svg>
            </div>
          )}
        </section>

        {/* SECTION 3: JOIN THE WAITLIST */}
        {typingFinished && (
          <section id="faq" className="h-screen w-full flex flex-col items-center justify-center relative px-6 flex-shrink-0 animate-fade-in">
            <div className="max-w-md w-full bg-white/10 backdrop-blur-2xl border border-white/20 rounded-[32px] p-8 md:p-10 shadow-[0_24px_50px_-12px_rgba(0,0,0,0.3)] relative overflow-hidden group">
            {/* Glossy shine effect overlay */}
            <div className="absolute -top-1/2 -left-1/2 w-[200%] h-[200%] bg-gradient-to-tr from-transparent via-white/5 to-transparent rotate-45 pointer-events-none transition-transform duration-1000 group-hover:translate-x-12" />
            
            {/* 1px glass rim */}
            <div className="absolute inset-[1px] rounded-[31px] bg-gradient-to-b from-white/25 via-transparent to-transparent pointer-events-none" />

            {!formSubmitted ? (
              <form onSubmit={handleSubmit} className="relative z-10 flex flex-col gap-6">
                <div className="text-center">
                  <span className="text-[11px] font-bold tracking-[0.2em] uppercase text-white/70 bg-white/5 border border-white/10 px-3 py-1 rounded-full">
                    {lang === "en" ? "Limited Spots" : "Beperkte Plekken"}
                  </span>
                  <h2 className="text-white text-3xl font-extrabold tracking-tight mt-4 mb-2 font-sans">
                    {t.waitlistHeading}
                  </h2>
                  <p className="text-white/80 text-xs sm:text-sm leading-relaxed font-sans">
                    {t.waitlistSub}
                  </p>
                </div>

                <div className="flex flex-col gap-4 mt-2">
                  {/* Name Input */}
                  <div className="flex flex-col gap-1.5">
                    <label className="text-white/70 text-[11px] font-bold tracking-wider uppercase pl-1">
                      {t.waitlistName}
                    </label>
                    <div className="relative">
                      <User className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-white/55" />
                      <input
                        type="text"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder={lang === "en" ? "John Doe" : "Jan Jansen"}
                        className="w-full pl-11 pr-4 py-3 bg-white/5 hover:bg-white/10 focus:bg-white/10 border border-white/15 focus:border-white/40 focus:ring-2 focus:ring-white/20 rounded-2xl text-sm text-white placeholder-white/35 outline-none transition-all duration-200"
                      />
                    </div>
                  </div>

                  {/* Email Input */}
                  <div className="flex flex-col gap-1.5">
                    <label className="text-white/70 text-[11px] font-bold tracking-wider uppercase pl-1">
                      {t.waitlistEmail} *
                    </label>
                    <div className="relative">
                      <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-white/55" />
                      <input
                        type="email"
                        required
                        value={email}
                        onChange={(e) => {
                          setEmail(e.target.value);
                          if (emailError) setEmailError("");
                        }}
                        placeholder="john@example.com"
                        className={`w-full pl-11 pr-4 py-3 bg-white/5 hover:bg-white/10 focus:bg-white/10 border ${
                          emailError ? "border-red-400 focus:border-red-400 focus:ring-red-500/20" : "border-white/15 focus:border-white/40 focus:ring-2 focus:ring-white/20"
                        } rounded-2xl text-sm text-white placeholder-white/35 outline-none transition-all duration-200`}
                      />
                    </div>
                    {emailError && (
                      <span className="text-red-300 text-[11px] font-semibold pl-1">
                        {emailError}
                      </span>
                    )}
                  </div>

                  {/* City/Region Input */}
                  <div className="flex flex-col gap-1.5">
                    <label className="text-white/70 text-[11px] font-bold tracking-wider uppercase pl-1">
                      {t.waitlistCity}
                    </label>
                    <div className="relative">
                      <MapPin className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-white/55" />
                      <input
                        type="text"
                        value={city}
                        onChange={(e) => setCity(e.target.value)}
                        placeholder={lang === "en" ? "London, UK" : "Amsterdam, NL"}
                        className="w-full pl-11 pr-4 py-3 bg-white/5 hover:bg-white/10 focus:bg-white/10 border border-white/15 focus:border-white/40 focus:ring-2 focus:ring-white/20 rounded-2xl text-sm text-white placeholder-white/35 outline-none transition-all duration-200"
                      />
                    </div>
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="w-full mt-2 bg-white hover:bg-neutral-100 disabled:bg-white/50 text-black font-bold text-sm py-3.5 px-6 rounded-2xl flex items-center justify-center gap-2 shadow-lg hover:shadow-xl active:scale-[0.98] transition-all duration-200 cursor-pointer"
                >
                  {isSubmitting ? (
                    <>
                      <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-black" fill="none" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                      </svg>
                      {t.waitlistLoading}
                    </>
                  ) : (
                    <>
                      {t.waitlistBtn}
                      <ArrowRight className="w-4 h-4 stroke-[2.5]" />
                    </>
                  )}
                </button>

                <div className="flex items-center justify-center gap-1.5 text-white/50 text-[10px] font-medium tracking-wide uppercase mt-1">
                  <Lock className="w-3 h-3" />
                  <span>{lang === "en" ? "No spam. Unsubscribe anytime." : "Geen spam. Meld je altijd af."}</span>
                </div>
              </form>
            ) : (
              <div className="relative z-10 flex flex-col items-center text-center py-6 animate-fade-in">
                <div className="w-16 h-16 bg-white/10 border border-white/20 rounded-full flex items-center justify-center mb-6 shadow-inner">
                  <CheckCircle2 className="w-8 h-8 text-white" />
                </div>
                <h2 className="text-white text-3xl font-extrabold tracking-tight mb-3 font-sans">
                  {t.waitlistSuccess}
                </h2>
                <p className="text-white/80 text-sm leading-relaxed mb-6 font-sans max-w-xs">
                  {t.waitlistSuccessDesc}
                </p>

                <div className="w-full bg-white/5 border border-white/10 rounded-2xl p-4 flex flex-col items-center justify-center gap-1">
                  <span className="text-white/50 text-[11px] font-bold tracking-wider uppercase">
                    {t.waitlistQueue}
                  </span>
                  <span className="text-white text-3xl font-black tracking-tight">
                    #{queueNumber}
                  </span>
                </div>

                <button
                  onClick={() => {
                    setFormSubmitted(false);
                    setName("");
                    setEmail("");
                    setCity("");
                  }}
                  className="mt-6 text-white/60 hover:text-white text-xs font-semibold underline underline-offset-4 cursor-pointer transition-colors"
                >
                  {lang === "en" ? "Register another email" : "Registreer nog een e-mail"}
                </button>
              </div>
            )}
          </div>
        </section>
        )}

      </div>
    </div>
  );
}
