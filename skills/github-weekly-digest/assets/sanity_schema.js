// assets/sanity_schema.js
// Add BOTH schema types to your Sanity project.
//
// In your sanity.config.js or schema/index.js:
//   import { weeklyDigest, dailyDigest } from './digestSchemas'
//   export const schemaTypes = [...existingTypes, weeklyDigest, dailyDigest]
//
// Then deploy: npx sanity deploy

export const weeklyDigest = {
  name: 'weeklyDigest',
  title: 'Weekly Digest',
  type: 'document',
  fields: [
    {
      name: 'title',
      title: 'Title',
      type: 'string',
      validation: Rule => Rule.required(),
    },
    {
      name: 'slug',
      title: 'Slug',
      type: 'slug',
      options: { source: 'title', maxLength: 96 },
      validation: Rule => Rule.required(),
    },
    {
      name: 'weekOf',
      title: 'Week Of (Monday)',
      type: 'date',
      description: 'Always the Monday of the week this covers.',
      validation: Rule => Rule.required(),
    },
    {
      name: 'weekLabel',
      title: 'Week Label',
      type: 'string',
      description: 'e.g. "Week of January 6, 2025"',
    },
    {
      name: 'publishedAt',
      title: 'Published At',
      type: 'datetime',
    },
    {
      name: 'excerpt',
      title: 'Excerpt',
      type: 'text',
      rows: 3,
    },
    {
      name: 'tags',
      title: 'Tags',
      type: 'array',
      of: [{ type: 'string' }],
      options: { layout: 'tags' },
    },
    {
      name: 'body',
      title: 'Body',
      type: 'array',
      of: [
        {
          type: 'block',
          styles: [
            { title: 'Normal', value: 'normal' },
            { title: 'H2', value: 'h2' },
            { title: 'H3', value: 'h3' },
          ],
          lists: [{ title: 'Bullet', value: 'bullet' }],
          marks: {
            decorators: [
              { title: 'Strong', value: 'strong' },
              { title: 'Em', value: 'em' },
              { title: 'Code', value: 'code' },
            ],
          },
        },
      ],
    },
    {
      name: 'stats',
      title: 'Stats',
      type: 'object',
      fields: [
        { name: 'totalCommits', title: 'Total Commits', type: 'number' },
        { name: 'reposActive', title: 'Repos Active', type: 'number' },
        { name: 'linesAdded', title: 'Lines Added', type: 'number' },
        { name: 'linesRemoved', title: 'Lines Removed', type: 'number' },
      ],
    },
    {
      name: 'projects',
      title: 'Projects',
      type: 'array',
      of: [
        {
          type: 'object',
          fields: [
            { name: 'repoName', title: 'Repo Name', type: 'string' },
            {
              name: 'projectType',
              title: 'Project Type',
              type: 'string',
              options: {
                list: [
                  'web app', 'CLI tool', 'library', 'config/dotfiles',
                  'data pipeline', 'API', 'mobile app', 'other',
                ],
              },
            },
            { name: 'summary', title: 'Summary', type: 'text', rows: 3 },
            {
              name: 'skillsDemonstrated',
              title: 'Skills',
              type: 'array',
              of: [{ type: 'string' }],
            },
            { name: 'url', title: 'GitHub URL', type: 'url' },
          ],
          preview: { select: { title: 'repoName', subtitle: 'projectType' } },
        },
      ],
    },
    {
      // Links to dailyDigest docs when generated via rollup
      name: 'dailyRefs',
      title: 'Daily Digests (rollup source)',
      type: 'array',
      of: [{ type: 'reference', to: [{ type: 'dailyDigest' }] }],
    },
  ],
  preview: {
    select: { title: 'title', subtitle: 'weekLabel' },
  },
  orderings: [
    {
      title: 'Week, newest first',
      name: 'weekOfDesc',
      by: [{ field: 'weekOf', direction: 'desc' }],
    },
  ],
}

export const dailyDigest = {
  name: 'dailyDigest',
  title: 'Daily Digest',
  type: 'document',
  fields: [
    {
      name: 'title',
      title: 'Title',
      type: 'string',
      validation: Rule => Rule.required(),
    },
    {
      name: 'slug',
      title: 'Slug',
      type: 'slug',
      options: { source: 'title', maxLength: 96 },
      validation: Rule => Rule.required(),
    },
    {
      name: 'date',
      title: 'Date',
      type: 'date',
      description: 'The date this digest covers.',
      validation: Rule => Rule.required(),
    },
    {
      name: 'weekOf',
      title: 'Week Of (Monday)',
      type: 'date',
      description: 'The Monday of the week this day belongs to — for grouping.',
    },
    {
      name: 'publishedAt',
      title: 'Published At',
      type: 'datetime',
    },
    {
      name: 'excerpt',
      title: 'Excerpt',
      type: 'text',
      rows: 2,
    },
    {
      name: 'tags',
      title: 'Tags',
      type: 'array',
      of: [{ type: 'string' }],
      options: { layout: 'tags' },
    },
    {
      name: 'body',
      title: 'Body',
      type: 'array',
      of: [
        {
          type: 'block',
          styles: [
            { title: 'Normal', value: 'normal' },
            { title: 'H2', value: 'h2' },
            { title: 'H3', value: 'h3' },
          ],
          lists: [{ title: 'Bullet', value: 'bullet' }],
          marks: {
            decorators: [
              { title: 'Strong', value: 'strong' },
              { title: 'Em', value: 'em' },
              { title: 'Code', value: 'code' },
            ],
          },
        },
      ],
    },
    {
      name: 'stats',
      title: 'Stats',
      type: 'object',
      fields: [
        { name: 'totalCommits', title: 'Total Commits', type: 'number' },
        { name: 'reposActive', title: 'Repos Active', type: 'number' },
        { name: 'linesAdded', title: 'Lines Added', type: 'number' },
        { name: 'linesRemoved', title: 'Lines Removed', type: 'number' },
      ],
    },
  ],
  preview: {
    select: { title: 'title', subtitle: 'date' },
  },
  orderings: [
    {
      title: 'Date, newest first',
      name: 'dateDesc',
      by: [{ field: 'date', direction: 'desc' }],
    },
  ],
}
