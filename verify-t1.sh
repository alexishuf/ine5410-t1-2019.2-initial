#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �=�v۶����@'!e�և'v�ֵ�ԧ�������]Z�l�H$CRq���g�_�}�� $�%9��v�'����`0��(>���b����Z�6�����Xo�O��iw׻��k��׻ߴڝ���7l�뱔�Y;!c�8�э����Mq����O������������������	��7�]߻��.�����\�?^pֺ������o���VϜ����������|o��[jמ�>�ڵ���;������[l��s��-k����N�X|�=(���Xs̖t�����g�s$�������7�g(Џn���2v��E�����:132�Kr�)��l)�5��q����q��'�w!�V�j�¿��n8��+����㵵����Za����w��6�}�Nf#ξ���\<��Y����F�,��s��j���=���)�
��FQ�`C�Qb6�p�: Y[5��;#���N| D�g�QyC@ՙ`1G[�O�K
����:��1��8�4u\��Nx>L*���MY9ٽ�LL0�M�M��M� b��A&N<�A��[�P��
y<=�9W5Q0�Ð�XK�#���p�{o���")Nld_˛a�i��O�((.`�+%�$�SDE�O#��b�j�����c�Y�U %�rP�]]e	{��L��q�a@�8H��m�h�lc����''�-J�+@���f��K6��$8k�L&��l7P�&�3�!�-�w�����tkEZ�	t�,�.h[i�.O``��'3iI���3�/RM��"U������ߵ��Ou'�d�I��)�v�2#����.��R����VW���v9RZ��㓘���c���v�?[ͧv��.2��NN��ײU�ɉy��o�u��$M���W��*��ܞ��V�|`
c�M�u�pfY� ?�c�'��fAyg���z�+��>-�_����>�����z�.N����G�$b�>�N�l�s��^o�$����b�s�1��z'U�E���*�����rh؈�]�%7����JjRNR�mE�t�ط�U��\]$�h~=R�IE�i�NM���T�A=�T$��&�ِ�&C&�l�5`�yf�Kѫ|����DZ��{��P�hI6��D>1G��O�M����&zqW��'+gS8�Ee��H�$��c���?��������v�*���C�KP R~����4�T���lHSa:��r;���I$��i��K�#�4w����f�%����T�$ͅ��n���1Z���=���#�ߙ〼ӣ~�'�(ːyp��,��H!�	�Jܣ� �A+�<,���h"G�]	��!j�3���@7�!Z��ޭ��V�tRs��A��?�i#�`|����|Z �KCk%m�Xj�5I��6ѮRR�!����e�OڠIWOX�15�sT:��$��re��x<�EZ�礇���nȁ�FN�K'"���0���4��.�5�eG�\�ĳ�CDd��Bn{��,1{S'^`�	���*mN�t�$�'
�{w��|hbC�	)pCք��}�-/���:��
s��3l����;���q�Q�{$e� �q� ��:H���I��Xψ9 y%\m��: N�?���T���ɣ|��sw�h֑k�G�G[���垔�1����S����ό�,�+��,� E,h�j�_0��?�Q�K /�:��쟪�0�`wR�xb+Hh�"�ْm���e�l�ݫ	�./[�uapMi_����}aoc���1�B��<���bM�O�%9m��V3�)��*z�.̼J	�S�"��+���G���D�Y���4���WN���������7Wǂ�N�p���������F���^����n��[��v�zK]���?<x�[Z�=��w������^C�aM�K*�`���������&�Zm�F�=�ѐ{#���f
K
�3��NF!�zK&�M��ǚ� �PE�@�
�8�㑟BHN�� ��ٞ<��
�
�'�i�)�ji;��E툾����7$�B��r�i�߳%�Lu.M8�u9�"��
���%]�d�`�N��LXh%��B���(��_�����������7��x%b�)���_YY1�\
����9�2�H�Z�+���{����9k:��k���_�J'����,�΅
�O+��@�C�e-/a��ҋ����}#���4��HAM)�UJVt~�F�z�~dh������+�E�ߏ���e�F������>������)�yxu,�������㵻��[I��_{�z{�o�P�q�S�QL�8	���H��FzݤG��`�A�5[0�5:�j2c�Gg���<J7`��A\��/��6.�TE��@�f��6�p}�!�����S���)�wi怿Zr���&�:c\K����{��sXo�f��<��￿��R{Ӏ&tp�3�1k��h^/�3Bo�m% �^���j ��TE�\^2M�ܶ,UI���_6O뛋=�PMF&�kQ��zSA��[�5��6�bj'�"�9���qC��?�z�k�>�����	hC8���4��;�V�S����g����7bdX(�&hj"F����
�Ӌ�Q��={Vh.	F����� I��E )R��Ç�%k�NI�T����U�%TO�~����x���F5]��K0������L���6�2�.�#��#�Ý81��R��Tof�I�ݔO@Պ�X��E�'+�����#�`�2��v�wȔ��g3X3�m�[���o#������#'��f��rq#ȕ�lu:����ڝ�w�;�F|�l���{�ۃ����4������m��S����u�b�h>��(^��ͳ�3�왢�Fk�����h��q�2K�<��7��[)M��ȟ���G/tP���.�9��G�?ӈ�R�^ԓ���l��H�a+�����P?cl�̋�s&��T%��9� Ȩ@d>4��D����{ 3*��s����0O�r��^�NI��s��(��:�F��x�&��[�p#I W''���z�9h���Q�������p3t͌��пv�L�	W����j6�:��F�z�«I���<����f�~[&�7�Tݚ�hq>d�'�x�Y��H�Z�XTW��G��;g~]ď�e���lS��F�8��+MN}�΁��4������k��������[Is�i'�aٝ�^�:	Tg�͛y.`g�N|�������������iR�qp��{;Gb�:����"�L�F<
\o��!m��r^�9m�V�&�hK!�����`���P�VTE:�#�G������T`P�H����Q%�}�T�	*�/0
M��Bʞ�"���C���*aPtX�<�d��][�b�Ҙy�sS�r��T�?uO�N"�#�Ξ��%�IE�j��c�Ԟ$n7��k��C��[���9��L1L��p�I�༌�Ց�a|�3,��/�A<��ȈM��"�ҠnE^�7T ��]J%�rbe��̄:��J�ܤXq�V%5� p����(<z�
T-�'���q�ܹY��b�Oe�Un�!��;1D���d`c�Q����@CӌTdOC�4 ˬ�IR�ܚ�|�yK?)�2���n��D [����y���dȥ�Y���!���w��6�Z]�--��lsb�21��U���B��
~�/�����4�pD�~�rŬ"$����$k��ا,������:�e�&��"(N���
.�����>�{^&tO��2�]�,�3q��<!��EEU��)���/�Ey+[���T�ZY�c������Ǟ�+]v55+��%�\�|�-TB?��^9!w1���F�
;�g�g��a�`�`ŧ��E@#2U�ҳGs�:��:w$ ���:U��2��,4XB��m�8��&\UqZm��M���h���UuF�+Ɣt3�Y-(m5e%��S����l�e���m+A���\'+I
��9�9Eī-�NFܧv�:Ye~�"�#��6�pJ��nR�|��D�������8��i��*���r�%\��HҜE||���\fT]�gC�O�s#��C���Ã�����N�ڽ	��E���o�M#;���ۛ��h��_�	fA� P�&�&d��l��<���L�I����	��Xڃ�������U����,VF>)b�C)˧�e�K�1Qm�=�7u�
�W���L�u�XW��"�t��EK�J���j �R��_��\���eޚ��PG�,�/N��C5��yz{p�������۽�q��y �l����0�юۃ7G�Zr��s;_�.�S�����+S$W��g7 �v�Y���,jJ�X��*�UȑZ�w�^��RŃ����rUz�U?Q���뗀>_�_*é�>�|jϙ|��4�@x(��WL��w5"G��]s�1y]��t|k5/�
	� a-�9��ru�?�����B,p�	i��!��GS�*�m͌puq�Y���j'vd�Ͼ����&�x��d��`��J����J��`+�x[_y��֓[[�x����V���h��IRk+� tW�v[�x����Ɠz ����'��&m�\�xJ���U�2mG��JP�?,�Z��D��/9��Z%g�p�à[�ϒ�+�ߖ�:��9·�t����!�.���[j ^r~��c�T�
%�B������#����f�>8@�Iݫ�+�ﱉ�Ujf����^���[TU�8����^1��L� ����573��e���) � 9j ��i��Ƕ�����n������o���Ap�9M%�7����m�0�g��u�L���ty0�����3M������Y�|�%�ӷ[ W�V�=�Ym��]��;c�Q�bnѿ��,ܛ��짟�mä_�����q�T���j�5����ٳv�(�̽sU���^X$��|ά��������Z�(��2��X��?���5�l�k�\��ө��?=�:��u?�����w�?n%���%��U��Z�q��=��tt�K(��#������;��u:�؉pP�9:��;!��G�%!��;��- K�A�l�G���`�mgH���|�|�#��`�N)z��ةL'Y'�C4�]=�����ZN[`��w�0�H�,#(<ˣ!�.T���?���U�5���a���(�������H������|d{�BUJ҉�X�.�F��D�2Q@�*U:ܕ��8�A8�qA�%�q�*�:w"Z
���M��z�L�sշL��Y��"	LRk&�3�)M�u�ʑP��\���pi�ތ/�g'��.����.c�{A�(��f�r�h�,�Ͳ��v��T�4�B_����#_��?�5}w3u,���k�B�g���;����l��|;�g��|��7�Bg���lN�=�׉~q �4����b�糗�Ъ����A�><��-��Gx����I/���7�/#�`��e�=���~IoF��Ȫ�����j`�W�{*Roc����w����\���)	,� �3�:~T�~����ĈO�#�#�w �ि�n�&y,6�����̝�sKf�j4��u�ޒk�x��s
o':P����D��j�{�C���0������t��k�o�Ʈ^�^3����r!���w�Ϗz���o�|�����	�_��l��G�o^��{�V�I��~qQ�ھ�M����m�y�������mt���?	ug�o!���_~|��ޭ\���m��	�����!�g��(�*�s:՟�!w���+/J��l8Gi�w�Ve� ����N3[�ykz>Ɓ���k["0�`�h[D�S �YOw��؆�ه��޳v�m#�9���$�����4{�uZ�v�k�^��v�Z�m6"�%)�M��O{v��O=����<H rT���ic��`0f���� ��l���r��VOl��Z�Q���/E�Y
�~����I�5��o�p���Q��\��uڵ��X�E�"�3���[)��&�E��I�r�a&�w��OT�#{�us0ptE��[ &�f�
�QΘ+�
{	6��e���;Eq�]���dKë�O~��;{p�.VD���d�)(AUx�1�bi�J���WT���f�"�j.81�9���s� Գ�Iu�*c��f�� #!��8���GV�8*2U�&�$������D�U���}�$��������[)���t�jH+�h|>nh
,�	Py��'�>v`V��`_*hZ!��~�?�X��ŏVaN�KD/�s[S�
���ώ��x��i�J�=Ņ(a�PR��o�1��O��Ҝ��@-�HE������CK3RQ
�D��F��U��@���/H^@"���|:�TU��n���]��RT	;V�"6YTQӵ�E��n�r������D�� �#V���`�T�S��UC ���� )����k�7�7^4F{�Fr&ק�_�ج=�Z�=�SKE�kh��Kh_D��o�_�IZ!��oy�b1�S2X��l��	%>�����w���q����'x�o�+���}'>�ô6W�V�hۦS��"S@w)ը3S��,$��tg�����}���?�rKvW,�|9�$3��4�z���Z��~5��T,��D�Z�R�ٹɉ"�t�{1u`f]�h��oe���'��ݖN����QK�XYav�A��Y��Y_�{�d�u��N�����㟅c�G;r}����!ƈSM��L��~D �O$��t�!�6Au[:5c���%���'I"|��
��;�0�m�};#���g�w��
Z��`˞UK�q�R�r�{��'�b7EWY�hgh���e�.fY7R�Qi�����zt_��=ģ�s6U�����Z}��;�/��@� �M��"��.0<�霨�O�`4���6���C��_5���,�7��c������RV-	���GuH7��@��I��&~��\�P���߮��]*q`V�
KFڣc��l�(5M�!6ͅE�͠QH*����@��}%��"�"��3i z��Yޘ�ۧ�;�Ut��h|�
���"NO�ު%�*��Ƽ}Mq�d1xI��­okc%D�m�mfu�N�ǕB�;�V��8;,�*;u/.��7S�	�K����+�����u�=��n�gA�c��ڭkOT�x�fezqM��h]7Vk6���j7RĠЍ��B�L�rie]ЖV�w5*�����5O����T
�^�\:1��D�"vz��`?���;�~eEĞVLOgN��{��P�\I�i:�h�
X�r6@�B�H�$G���
1�QGi$;�(o���&������So�}!�/���"��H>���c/�|�"��`��6�~�Wm�u��!��<�g<D���]�`�_�n��`g�����o�;��b�A�+�[���H�>�:/
�wd������PYC����p�3;x�^�gb�"՗>_#�fRJryϓB���+���l<����Ls��A^%�����֗���m:t�v�%��
#�tTW3�C����8P��@/9��C2�F��ˀ�"�q��m3g@J��y�BFO�t�p�$�	$,7�D�<(si��M�'u�tP�y:m�N;{t��c��}�1~�[_(�E90h���x��s��N��#�,�{9��3�����B�aO�4]���1)vh����Z?�	S���V�Zn9\l�K�bI�eM��V +-w���ݾ4�DJ��\3��`J�1�<�N�h�+z�ǻۯ�O��������UA�c��}�G&=�{��G��G��ói�xK������>���*�DaPU�d-�E��_
����ÎwuS|����K�]X%|*06�6�y�6����pi�#�*�E���m[�x��=��F����p� =�;�
�^����y���j�|�g��%�ɴP����ę��a�<�X·$�fA�b��2�2U�T��j��e���f��13�s`���.̓ᥛ��e���3�?��EG6�V�����e��,�4�J%�Aik�$#a���|*
U��C�$5*+�: ��[�V�/f�1.ve^�(�5%��k�:q}LƦ]\�w�b�D#L8�}o�ΦD��
�����`[YѲTGrI~�25�fw��mJY�c`T2�Jw�l���� ��4�.%���DfNe��*?H[汭������jNe���!`Y�,??K�*�6�YT�Y�T�0��̯o��3]�)`w�֡ԭ�(#߁�R(�CS�|A����q��Q0r~r9jy3�o�邺-R��O�!f6�7�dO��a�l�Ұ#8F,�{��9�@��r �4@���~�aŒҴ�HP2�Xr^Yl�٫����̜�-if��r�A��$�TЗ0����k+�x�5&�^!�ͬ~��vّ�i�$yS��*�<�����.�d4b�ߖc��Y埛�3�*)������(�j�xp��|#p%��d-sC�������E�g��U���o�N��A�?���\S=��C��N-t���3T�ϔG�.>���L {Z���g*�mJ��-��#����iHE�p��X���cE�GC)`���˜�d��7
�2�UVW�Hj�Tf���65S�^fojԼ2�C�X�oe��`ZP�^�'Ռ��T���b���0ݪ� �����eû����z�z������h���v5�Sv��Mq�R{VB2���<3�Y}R��a����K7��E/rp��������ls1Uد���ii�Ю��=zţt�������i��t4>y��S6�*H��Gߜt���E�\��HW�vr�� ����A�|8ffT�: y� {���K�ǯʷ���S_x �W�e�x_s��*m�v�����v����ߊ��D�ku7�l�=Sb���� �2(����d��;�k�S���,Wsm>��c��G��M�B��Ns���j�!>��j��i"���\߉E<~G���ۥs����r�z����[�i�@;`��-˵���E�زޯ���¤�z�/]�R|�Zt���^�h|����Ux ��R���s�o�#}��A�^)�K�^ƿu"F�f����9�x�WYC������8���� 潉M\�o�<���u��4d�P�4$[SYU=(�l�rγ@5�
�Y�J�26��ޚ��)�O���3�{O�b��SkQ�e�c��f�=v@ b
���
�0z �Ȅ�OO�7H�)TsF��݋H����(=��4����)n_ ��J��aږ<�3I��Ȩ�+�����Z�fS�yq[�%'��iVK�䲼�/�����z�QvPf��l�}t��ܳ0kQ����O�\�j+�Q�S�Ɍ&yƬ\�Dd��觴h��U|g��'�q�7���f7�S�65��A�7a���ܬ̩O�)4kkԜ�6�w��F�d�]�T�~F�0����zH0��Gv3���+ezU��J��[�:�|�<�R��_�_����@�5eB���*�c�S�mA�-B�D��2���)�4r27u�d������2y�g�Y/˻3��=*�>&?Tr��.�d�iTa%\@&��3�raU�4L�}�jS��L�)���Y$�f�K�N�mvA��%�[��h���M����_��CRS5����2��U��7��3���}�:��#l�0�p�QO�zqv�[m�Vf�ȳ� �F�I ���1}�aAY�_C��Qg45
Tm`�!*�LQs��ן���3��k�t��Zni�p*��am<�w�t%��v5�Q���y7�S�3��H�%�Y���"�.�ո;6j�k��s�6����������t��>����9�Y\�[3�ǲ��|�re��G5�Эrc�����[/��^-�	9��b��L5YP�鰠~fx�i%v8��`J	,hr�y"�p�0 ������hu�a����y7;A,�]c]Y��Ok�����qq��ژ'M�ž�$��E�ri���5|�K��[6�ӷ`�g��؏�._gcY�C�&鯔��h ̻�	�rAr��\�Q-�Wx�]��9�of���H��G9�et�8�a��^�2���ǰJCE'���kd���l�W�NA?��!;&f�� �|/�,
gxT̅�$����;�&(a��a�%��~�#LE�N�$
/" W=�HQ��9Ӟ�Ь��ܘ��������w�qi�R;;����vP0o���]s"R�),-	_��'G4U̾"�-�$�U�NŰP07m
⯨��+K��2>f^2��T�iƧ�7ΈE�ù�V��|cuN��ZP�U�M|��Ei�w#�˪.��>,��z��|�و�~�n�U�^�.s���*}^`��?�,M��nc���vV�v
���XRl=恨�B�*_���TeOo�*�v���l��/�Cm!mT�����H�����ϖ���F1�����`��`��ze��;+�Ư�^1���$��3C
(�fF�?f�j�hb�QTJ�'�*'��8�m�*��$�*��
S���Al |��W}��٫� ��-2�b�w�g����� ���4f��ĸ��qcCˈ�/�[8��(�H�0y[�O����p|v�1�TjWAeh��k�*V�`^��Vǜ�RVVG���q&X�Ѣ��(�4Yte�<��4vY>�R��/����W~}������VJ镼�rG7�j7�xԌ��(�,-+^���V��{���3�..� �Z�}H�����Y{���VDu����$��dk��y&i�Ջ�j�%L2�L�1)ﲶ�_�T%���;̞�yEv>#�5��[�[�ɚ]@��E�S��h������� �,k�Y��e��ȟ�4��k��ֈ�������e/s������-�w���U��=?uSB����xCR���i0���3�:E�F�� cTX�P5Y��wj��^ض��X����t�ҩ�����ɱ��!+������#�A�?������2��O�a�>o�x������#�<�̬!C�Fr���)��;=eY���HJ�^ư�y��-�Wn��^���e2isó��l�з|N�֋{��������ۨ���h��㵧����m����0q�xA�������xm9��R2e���X�O9��B�@ò�˧@�I������š4=����7�!�6K�KO.gv_9�.��K'��1Ӡ��,����z=r<�}9�2��t���������@���pz6v�E�py�H�p��D�Q��W\=�n�5s�ZCdY���#��|��ق��ZC̊N�_����OC�0��0�Cf��f7��1��$J�I5�^�әK��4Ә����C7�	J���c����A"Ͽ�b��_�\����u��$ςi�%�=��.���c��f%����x1�~Y�E��'E�����Ou��	�^���P��μ�w�ė�ȶO��e���\����~A>��uI$|�8�b�U
bv|��>��>=z}�ɽ��3���^0��[�.�}���]���6��/�Je��o�*�j��7^��d����X��@�����n�t�P���G&Ta|�~��5�+���;�[ �WHS�`��E��>����J�Ƒp���C
,�6�Țu��I9�|7�&�[h��_��:yL��{ВŌVt��WH�^����u��&�ߑ�7-�"�d5EP�M� o	XE�
?\ &t�3&cÏo����R�r��8���\]�7%c����UxKֺ����5�_��I6�:~@��Ձ lc��|(4/Q���Hjx��ht��;R���VFa�Z��<S��K��F#����;M'qA�H�����a��d!.\�T���u����R��J�Q��qX�߮d�_,��o�|���=}����p9�o�l?��zq�)6gHggptx���`{pr��x{w���ڟ��{�t.H�p�t��� �?Hs�yxb��������թm�a�0�
��&tx�n:�Q��?J����Ǣ�)־���j���ޗ�r�kg��ޫݓMԥvc��FS���b7��>U}g����c�x1q�L�(}�!X�hj��@�
�]���g�ۉ]x��:	�1�#�M�p"|C7�<ₒ9��! �8p���q)4a�u�.Lu�)T=w���A@���u��_׿L"�=]��x���"�aQ:MhU�KлT@�]J���j���n>�9nC��$�l�z�O�wF�x�� ��Io��p�͜`�:�4	;�r��΅����~�䈏��)�����������M���ꞎؐ�����1�������F�7	-ƅ'��ͷ h�D#�懶�rwkg�X{~	�>��&n�m��6��H$�i�1%0q5�Kq{���&ca�8�dct�wԒa�I�a��*�����	��zqx��F}��Gv�Qu�Z7�#'��gqB�֬�{���}��~AV�8������m�;N�럑� ���Sڔ�ڌ/���o /ҙ��&���ޱ�zB��ma���$��e�g؍b�K�`_��N_"��js{�&�]��0�;i�N|��@�����ے =�Ǚ2��?]� �}�����Z�^���m�#;�}㱗_t��/��n�]����rG��_o��~�}�w��$���I�8(�y-d��M��C�I��p��?_Њ/w����-P\ya���dZ�����3�1�V�aӑ�v��}��38�p����G���*�v��Xw�\}��PAn3�-մ۬&�n���9Q���u�J�s9� {G]�6�IXsE �f�[ߑI�L��t"\�\�`gݑGp`��ă����8݂v�q�CE��g�%�n���{�	K_"i-�Y����%(��T��>?�t�����z�{qL7a��0&��#�(�}��46���'���ЅC#A����7���=zy��o،�
kCo���Ȇ(�=�Ƈ:�Y(�/1r�w����&�a#�/�F���ldB�j\���
��sᰵ.r�!�r���qd���@)��b.Q�b&ᩏ"dn(S�K�2���.�l������Ĳ��u��g���P*硣�Vj�0���GL>	�ĥ�B�vD�=�,X>g�^���(�h �������|l�#�q�x�{\�.ۑy�����}�Ƚ�@��"�����'oG��0�ގ��2�t��fG�A>|��@/����:>���4[�ևD�Ϫ���M���.y�>�G֝ּ��6����8��u��d��Oɷ֝;y��m=��M��"���tJwrz���:�N��W��
��d�9\_'��e
 ��C7|;���uǟa�%�.��zc%����8�O�AA�.U���0�8�c]Y񂉔\��x�0�!�C�s�����>�Kd��:Cu���e�|�O�C�g���n�A�@]�c�e2�레�Q��w`��D3�� ��[�"z�l��Sw.��j�!��F��F�"V]�c�
�):]ο�����u�@ĨmHͯ� 1]i2:Y�j�a���J'���7`H>y���ٚy1,,�������OB�P� Ͻ�YA�$�'1������6�utXo�.�������I�f):D�h��g]�a��K'n�uy��'9���]����q�]��?���B]L�B�����y�R���_��xC�4_�,}��W,��bm�E�7钦;��`@����jK;����G����(U(E�1����ij����c�q��xw{����F�.��-G5㻑b��1;t7V*5Ѵ�����2���Џ�n�y�
7q�)(��*�d��*o��|��.��%#���z?iY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eYn��?��_I @ 