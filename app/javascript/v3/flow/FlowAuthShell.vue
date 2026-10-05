<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useLoginPage } from './useLoginPage';

// The frame every auth screen sits in (login, SSO, forgot and reset password, signup).
//
// With no installation login page, it renders Chatwoot's own wrappers unchanged, so the
// screens look exactly as upstream: `header` is the logo-and-title page (login, SSO), `plain`
// the card-only one (password screens), `bare` adds nothing (signup brings its own frame).
//
// With one, the page's content goes into a single solid surface (logo, title, subtitle, the
// form, then the support and legal links) over the chosen background, or into the left half
// of a side panel layout. No text ever sits on the background except the panel message, which
// has its own scrim, so any uploaded image keeps the copy readable.
const props = defineProps({
  variant: {
    type: String,
    default: 'header',
    validator: value => ['header', 'plain', 'bare'].includes(value),
  },
  // The screen's own title (Chatwoot's text); the login page's copy replaces it on `header`.
  title: { type: String, default: '' },
});

const store = useStore();
const globalConfig = computed(() => store.getters['globalConfig/get']);
const { page, enabled, copy } = useLoginPage();

const isSplit = computed(() => page?.layout === 'split');
const background = computed(() => page?.background || {});
const isImage = computed(() => background.value.kind === 'image');

const backgroundStyle = computed(() => {
  if (isImage.value) {
    return background.value.image
      ? { backgroundImage: `url("${background.value.image}")` }
      : {};
  }
  return background.value.css ? { background: background.value.css } : {};
});

const backgroundClass = computed(() => ({
  'flow-auth__bg--drift': background.value.animation === 'drift',
  'flow-auth__bg--zoom': background.value.animation === 'zoom',
}));

const veilOpacity = computed(() =>
  isImage.value ? (background.value.overlay || 0) / 100 : 0
);

const heading = computed(() =>
  props.variant === 'header' ? copy.value.title || props.title : ''
);
const subtitle = computed(() =>
  props.variant === 'header' ? copy.value.subtitle : ''
);

const links = computed(() => {
  const options = page?.options || {};
  return [
    options.support_url && {
      key: 'support',
      href: options.support_url,
      label: options.support_label,
    },
    options.terms_url && { key: 'terms', href: options.terms_url },
    options.privacy_url && { key: 'privacy', href: options.privacy_url },
  ].filter(Boolean);
});
</script>

<template>
  <!-- Chatwoot's own wrappers, unchanged, when no login page is set. -->
  <main
    v-if="!enabled && variant === 'header'"
    class="flex flex-col w-full min-h-screen py-20 bg-n-brand/5 dark:bg-n-background sm:px-6 lg:px-8"
  >
    <section class="max-w-5xl mx-auto">
      <img
        :src="globalConfig.logo"
        :alt="globalConfig.installationName"
        class="block w-auto h-8 mx-auto dark:hidden"
      />
      <img
        v-if="globalConfig.logoDark"
        :src="globalConfig.logoDark"
        :alt="globalConfig.installationName"
        class="hidden w-auto h-8 mx-auto dark:block"
      />
      <h2 class="mt-6 text-3xl font-medium text-center text-n-slate-12">
        {{ title }}
      </h2>
      <slot name="after-title" />
    </section>
    <slot />
  </main>
  <div
    v-else-if="!enabled && variant === 'plain'"
    class="flex flex-col justify-center w-full min-h-screen py-12 bg-n-brand/5 dark:bg-n-background sm:px-6 lg:px-8"
  >
    <slot />
  </div>
  <slot v-else-if="!enabled" />

  <!-- The installation's login page. -->
  <main
    v-else
    class="flow-auth relative flex w-full min-h-screen overflow-hidden bg-n-background"
    :class="isSplit ? 'flow-auth--split' : 'flow-auth--background'"
  >
    <div
      class="flow-auth__visual absolute inset-0 overflow-hidden"
      aria-hidden="true"
    >
      <div
        class="flow-auth__bg absolute inset-0 bg-cover bg-center"
        :class="backgroundClass"
        :style="backgroundStyle"
      />
      <div
        v-if="veilOpacity"
        class="absolute inset-0 bg-black"
        :style="{ opacity: veilOpacity }"
      />
      <div
        v-if="isSplit && copy.panel_message"
        class="absolute inset-0 bg-gradient-to-t from-black/60 via-black/20 to-transparent"
      />
    </div>
    <p
      v-if="isSplit && copy.panel_message"
      class="flow-auth__message absolute hidden lg:block m-0 text-xl font-medium leading-snug text-white text-balance"
    >
      {{ copy.panel_message }}
    </p>

    <!-- `bare` (signup) brings its own card: it only gets the background. -->
    <div v-if="variant === 'bare'" class="relative w-full">
      <slot />
    </div>
    <div
      v-else
      class="flow-auth__column relative flex flex-col items-center justify-center w-full px-4 py-12 sm:px-6"
    >
      <div class="flow-auth__surface w-full max-w-md">
        <header class="flex flex-col gap-2 mb-8">
          <img
            v-if="globalConfig.logo"
            :src="globalConfig.logo"
            :alt="globalConfig.installationName"
            class="self-start w-auto h-8 mb-4 dark:hidden"
          />
          <img
            v-if="globalConfig.logoDark || globalConfig.logo"
            :src="globalConfig.logoDark || globalConfig.logo"
            :alt="globalConfig.installationName"
            class="self-start hidden w-auto h-8 mb-4 dark:block"
          />
          <h1
            v-if="heading"
            class="m-0 text-2xl font-medium tracking-tight text-n-slate-12 text-balance"
          >
            {{ heading }}
          </h1>
          <p v-if="subtitle" class="m-0 text-body-main text-n-slate-11">
            {{ subtitle }}
          </p>
          <slot name="after-title" />
        </header>
        <slot />
        <nav
          v-if="links.length"
          class="flex flex-wrap items-center gap-x-4 gap-y-1 pt-5 mt-8 border-t border-n-weak text-label-small"
          :aria-label="$t('FLOW_LOGIN_PAGE.LINKS')"
        >
          <a
            v-for="link in links"
            :key="link.key"
            :href="link.href"
            target="_blank"
            rel="noopener noreferrer"
            class="text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand rounded-sm"
          >
            <template v-if="link.key === 'support'">
              {{ link.label || $t('FLOW_LOGIN_PAGE.SUPPORT') }}
            </template>
            <template v-else-if="link.key === 'terms'">
              {{ $t('FLOW_LOGIN_PAGE.TERMS') }}
            </template>
            <template v-else>{{ $t('FLOW_LOGIN_PAGE.PRIVACY') }}</template>
          </a>
        </nav>
      </div>
    </div>
  </main>
</template>

<style lang="scss">
/* Not scoped: the screens' own cards are slot content, and inside the surface they become
   plain sections of it (one surface, no card in a card). */
.flow-auth__surface > :is(section, form) {
  margin: 0;
  padding: 0;
  max-width: none;
  width: 100%;
  background: transparent;
  box-shadow: none;
  border-radius: 0;
}

.flow-auth__surface > :is(section, form) + :is(section, form) {
  margin-top: 1.5rem;
}

/* Pieces of the screens that paint their own background to mask a line (the "OR" divider)
   take the surface's, whatever layout and theme it is in. */
.flow-auth .section-separator span {
  background: var(--flow-auth-surface);
}

/* Links under a screen's title (e.g. "or create a new account") follow the start-aligned header. */
.flow-auth__surface > header > .text-center {
  text-align: start;
}

/* Card over the background: one solid surface, lifted. */
.flow-auth--background .flow-auth__surface {
  --flow-auth-surface: rgb(var(--solid-1));

  padding: 2rem;
  border-radius: 0.75rem;
  background: var(--flow-auth-surface);
  outline: 1px solid rgba(var(--border-container));
  outline-offset: -1px;
  box-shadow:
    0 24px 48px -12px rgb(0 0 0 / 0.25),
    0 4px 12px -4px rgb(0 0 0 / 0.12);

  @media (min-width: 640px) {
    padding: 2.5rem;
  }
}

.dark .flow-auth--background .flow-auth__surface {
  --flow-auth-surface: rgb(var(--solid-2));
}

/* Side panel: the form on the plain page surface, the visual on the right from lg up. */
.flow-auth--split .flow-auth__column {
  --flow-auth-surface: rgb(var(--solid-1));

  background: var(--flow-auth-surface);
}

.dark .flow-auth--split .flow-auth__column {
  --flow-auth-surface: rgb(var(--background-color));
}

@media (min-width: 1024px) {
  .flow-auth--split .flow-auth__visual {
    left: 50%;
  }

  .flow-auth--split .flow-auth__column {
    width: 50%;
  }

  .flow-auth--split .flow-auth__message {
    left: calc(50% + 3rem);
    right: 3rem;
    bottom: 3rem;
    max-width: 32rem;
  }
}

@media (max-width: 1023px) {
  .flow-auth--split .flow-auth__visual {
    display: none;
  }
}

/* Slow and quiet; off entirely for people who ask their system for less motion. */
.flow-auth__bg--drift {
  background-size: 200% 200% !important;
  animation: flow-auth-drift 24s ease-in-out infinite alternate;
}

.flow-auth__bg--zoom {
  animation: flow-auth-zoom 40s ease-in-out infinite alternate;
}

@keyframes flow-auth-drift {
  from {
    background-position: 0% 50%;
  }

  to {
    background-position: 100% 50%;
  }
}

@keyframes flow-auth-zoom {
  from {
    transform: scale(1);
  }

  to {
    transform: scale(1.08);
  }
}

@media (prefers-reduced-motion: reduce) {
  .flow-auth__bg--drift,
  .flow-auth__bg--zoom {
    animation: none;
  }
}
</style>
