/*         ______   ___    ___
 *        /\  _  \ /\_ \  /\_ \
 *        \ \ \L\ \\//\ \ \//\ \      __     __   _ __   ___
 *         \ \  __ \ \ \ \  \ \ \   /'__`\ /'_ `\/\`'__\/ __`\
 *          \ \ \/\ \ \_\ \_ \_\ \_/\  __//\ \L\ \ \ \//\ \L\ \
 *           \ \_\ \_\/\____\/\____\ \____\ \____ \ \_\\ \____/
 *            \/_/\/_/\/____/\/____/\/____/\/___L\ \/_/ \/___/
 *                                           /\____/
 *                                           \_/__/
 *
 *      MacOS X common quartz (quickdraw) gfx driver functions.
 *
 *      By Angelo Mottola, based on similar QNX code by Eric Botcazou.
 *
 *      See readme.txt for copyright information.
 */


#include "allegro.h"
#include "allegro/internal/aintern.h"
#include "allegro/platform/aintosx.h"

#ifndef ALLEGRO_MACOSX
   #error something is wrong with the makefile
#endif



/* setup_direct_shifts
 *  Setups direct color shifts.
 */
void setup_direct_shifts(void)
{
   _rgb_r_shift_15 = 10;
   _rgb_g_shift_15 = 5;
   _rgb_b_shift_15 = 0;

   _rgb_r_shift_16 = 11;
   _rgb_g_shift_16 = 5;
   _rgb_b_shift_16 = 0;

   _rgb_r_shift_24 = 16;
   _rgb_g_shift_24 = 8;
   _rgb_b_shift_24 = 0;

   _rgb_a_shift_32 = 24;
   _rgb_r_shift_32 = 16;
   _rgb_g_shift_32 = 8;
   _rgb_b_shift_32 = 0;
}



/* osx_qz_write_line:
 *  Line switcher for video bitmaps.
 */
unsigned long osx_qz_write_line(BITMAP *bmp, int line)
{
   if (!(bmp->id & BMP_ID_LOCKED)) {
      bmp->id |= BMP_ID_LOCKED;
   }

   return (unsigned long)(bmp->line[line]);
}



/* osx_qz_unwrite_line:
 *  Line updater for video bitmaps.
 */
void osx_qz_unwrite_line(BITMAP *bmp)
{
   if (bmp->id & BMP_ID_AUTOLOCK) {
      bmp->id &= ~(BMP_ID_LOCKED | BMP_ID_AUTOLOCK);
   }
}



/* osx_qz_acquire:
 *  Bitmap locking for video bitmaps.
 */
void osx_qz_acquire(BITMAP *bmp)
{
   // Check if the bitmap is not already locked
   if (!(bmp->id & BMP_ID_LOCKED)) {
      bmp->id |= BMP_ID_LOCKED;
   }
}



/* osx_qz_release:
 *  Bitmap unlocking for video bitmaps.
 */
void osx_qz_release(BITMAP *bmp)
{
   bmp->id &= ~BMP_ID_LOCKED;
}



/* osx_qz_created_sub_bitmap:
 *  Makes a sub bitmap to inherit the GWorld of its parent.
 */
void osx_qz_created_sub_bitmap(BITMAP *bmp, BITMAP *parent)
{
   bmp->extra = parent->extra;
}



/* _make_quickdraw_bitmap:
 *  Creates a BITMAP using a QuickDraw GWorld as backing store.
 */
static BITMAP *_make_quickdraw_bitmap(int width, int height)
{
   BITMAP *bmp;
   CGContextRef context;
   CGColorSpaceRef colorSpace;
   Rect rect;
   char *addr;
   int pitch;
   int i, size;

   colorSpace = CGColorSpaceCreateDeviceRGB();
   context = CGBitmapContextCreate(NULL, width, height, 8, 4 * width, colorSpace, kCGImageAlphaPremultipliedLast);
   CGColorSpaceRelease(colorSpace);
   if (!context)
      return NULL;

   addr = CGBitmapContextGetData(context);
   pitch = CGBitmapContextGetBytesPerRow(context);

   if (!addr) {
      CGContextRelease(context);
      return NULL;
   }

   /* create Allegro bitmap */
   size = sizeof(BITMAP) + sizeof(char *) * height;

   bmp = (BITMAP *) malloc(sizeof(BITMAP) + sizeof(char *) * height);
   if (!bmp) {
      CGContextRelease(context);
      return NULL;
   }

   bmp->w = bmp->cr = width;
   bmp->h = bmp->cb = height;
   bmp->clip = TRUE;
   bmp->cl = bmp->ct = 0;
   bmp->vtable = &_screen_vtable;
   bmp->write_bank = bmp->read_bank = osx_qz_write_line;
   bmp->dat = NULL;
   bmp->id = BMP_ID_VIDEO;
   bmp->extra = NULL;
   bmp->x_ofs = 0;
   bmp->y_ofs = 0;
   bmp->seg = _video_ds();

   bmp->line[0] = (unsigned char *)addr;

   for (i = 1; i < height; i++)
      bmp->line[i] = bmp->line[i - 1] + pitch;

   /* setup surface info structure to store additional information */
   bmp->extra = malloc(sizeof(struct BMP_EXTRA_INFO));
   if (!bmp->extra) {
      free(bmp);
      CGContextRelease(context);
      return NULL;
   }
   BMP_EXTRA(bmp)->port = context;

   return bmp;
}



/* osx_qz_create_video_bitmap:
 *  Tries to allocate a BITMAP in video memory.
 */
BITMAP *osx_qz_create_video_bitmap(int width, int height)
{
   if ((gfx_driver->w == width) && (gfx_driver->h == height) && (!osx_screen_used)) {
      osx_screen_used = TRUE;
      return screen;
   }
   return _make_quickdraw_bitmap(width, height);
}



/* osx_qz_create_system_bitmap:
 *  Tries to allocates a BITMAP in AGP memory.
 */
BITMAP *osx_qz_create_system_bitmap(int width, int height)
{
   return _make_quickdraw_bitmap(width, height);
}



/* osx_qz_destroy_video_bitmap:
 *  Frees memory used by bitmap structure and releases associated GWorld.
 */
void osx_qz_destroy_video_bitmap(BITMAP *bmp)
{
   if (bmp) {
     if (bmp == screen) {
        osx_screen_used = FALSE;
        return;
     }
     if (bmp->extra) {
         if (BMP_EXTRA(bmp)->port)
            CGContextRelease(BMP_EXTRA(bmp)->port);
         free(bmp->extra);
      }
      free(bmp);
   }
}



/* osx_qz_blit_to_self:
 *  Accelerated vram -> vram blitting routine.
 */
void osx_qz_blit_to_self(BITMAP *source, BITMAP *dest, int source_x, int source_y, int dest_x, int dest_y, int width, int height)
{
   CGRect source_rect = CGRectMake(source_x + source->x_ofs, source_y + source->y_ofs, width, height);
   CGRect dest_rect = CGRectMake(dest_x + dest->x_ofs, dest_y + dest->y_ofs, width, height);

   CGContextRef source_context = BMP_EXTRA(source)->port;
   CGContextRef dest_context = BMP_EXTRA(dest)->port;

   if (!(dest->id & BMP_ID_LOCKED)) {
      dest->id |= BMP_ID_LOCKED;
   }

   CGImageRef image = CGBitmapContextCreateImage(source_context);

   CGContextDrawImage(dest_context, dest_rect, image);

   CGImageRelease(image);

   if (dest->id & BMP_ID_LOCKED) {
      dest->id &= ~BMP_ID_LOCKED;
   }
}
