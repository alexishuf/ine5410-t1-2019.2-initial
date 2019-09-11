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
�      �<�v۶����@'!e�և?�J��J�S����M�ھ<�ټ�H��b��f������b;3 H�KrR'��78>����` �(>���r��K-H����lo����J�����F{�����k�;���{l�˱��Y;!c��	�v�j�E��GS������h���?�|������:As<��{w��E�����������=ֺ�����p���Vϝ����Ϋ���|���[jמ�>�ڵ���;������l��s��-k����ζY|�=(���Ys̖t�����g�s$�������7�o(�k7fmz��\��z�Tpf��B�%�ŔQm���K�8Q���8����ӻA�F�R�_�aw�����ԁcFt��ow��
����6��Fz�z��l��wQ<r���g5=+t��|�h�g�B~��1��z1���?`L�T`�u6������ڮɟ��8M p�K !�<�8C�Z����9�~ʽXR�
ݘ�בE��5���q=8��0�^>X�7e�L,d�{��21�T<6�7�s���È%v�8��:i�Am
+��,�X[���D� C�c-��|�z���!��98h�:��8��}-o�է�:>�����Mr��8��L�S>�xl>J�Y��"�W�UgYV�4�A	vu�%�	�3}�m���� ��Ӷm�ղ��R���v�(Q� �JP����/ـ�ଡ3��C��@՛p�$�,��ީ_�gVҭiY'����H�m�]�<�m�ͤ%�gX���H5n��Ua��#��~��7?՝T�)'Q���$�aʌ�3���CK��V�"��ˑК�P?9��Y�<q���4���|j���"�,���.~-[����'���n��&�I�R� ��Q%`���'b��0��Xk��#�z&�YV:�/��g�	w�YP�Y�4����>��
�W�c��O'�/+�����	'��b�[��KV'b�Ź�g�w^���i���9�R@=����"N��\`�M�
94l�Ǯ�au��h%5)')նG��F:�Y�;֪jw�.U4�)ؤ�Դݦ����q��Z*�W��lHY�!�T��0�<3ޥ�U���zA"-S�=�}�@	�$�pt"	��#�ɧæ}��l���O󓕳)����$cjx�`��/��/���^�w|9�=�?��k�������"��`A8�-�9� �}>�T�$���8�bI�{���/�8���D���d�m�c"�*Is�:B���l�Vd�d�p`���Ĉ�w�8 ������)�2d\a0K�%R��d� ���?�8dЊ1ˬ� ��{W?z����{�%�h�����w+����$�Ԝ��B���ďx�)X�h�-����Z��E�8��kM�"cןMF�+���f�%b�y��6h��VzL2��N~�=�5�\3=Ofѥ��9�!q@��r賑;�ʉH�1�Lc�A9���`͆hّ&(��П��泐�^4;O��ԉ��Xoej�J��5�,�*��ޝ�-:�ؐ�jB
ܐ5�!"E�f��:��ά���8b�[�~�|��?�0��c�sT�IY%�r\'H=��#�uR-#�3bH^	W۰���@�O�G=$�|z�8_����]�:�`M���x� ���ܓR:A���pjs�򙑟%rC��%���B��f� �<�t	�%�Q�Q��S5��N�O,b	M[d3[���Y�������]W7���e�.n)���7R���mLYY�["�Th�gP��X�	�ɶ$����j� 4�|QE�ʅ�W)Av�SS|����(3�!��<kqu�����ޠ��)��:#޼r����Xp������[�o��_#�������o�0��-uj�Go����a��-�՞��{?����[Z�����ǌ%�k��g	��X�f�I�6q���hȽ�����3�%�y���Uv'��{�%����w�c�f O��m�g�V���O!$�|�J `�lO��	��|�K���4~��b���ݢvD��U���d��u��4���u�:�&�l��^�[xE`ϒ�C��y'@q&� ���]!�W~���|�bw�ij�Q�C��x��ٔ�l诬�R.^I�҃���N$v+����}F���tA�5]�5����Oh�m��A
��~�B�ͧ�PY ȡ�����z@�E�s��߾�L��al�����*%+�K?b#p�b?2
4��[LGȇ���O���nm�2V�������_>������)/xxu,������c��-��$}���x��׷��(�G�8�ީ�(��f���z�Ip��n�#\r����m��|5�1�sg�n%��R� .O�Z�KF�"[l D�IL^������O�Iy�L_�ͻ4s�_-9��qV�1����c����} ���7X�	s���?<x�`��e@:8���昵Ys������ն ]/I���	 ��=�"v�	./���]n[������߷��[�=�PMF&�kQ��zSA��[�5��6�bj'�"�9���iC����z�k�>���	hC8���4��;�V�S����g����7bdX(�&hj"F����
�Ӌ�Q��={Vh.	F����� I��E )R��G�%k�NI�T����U�TO�~����x���F5݀�K0������L���6�2�.�#��#�Ý85��R��Tof�I�ݔO@Պ�X��G��+�����c�`�2�����)��?8w��~�L�V.癩�����,���׾��_#=p�ވ��m�m�`ogp���?�w����:u�s �сNX���r���`#�<;>���̞)Im��k|X�d�a���G��P������0a�b��5G��&xz�C�"ܔV�����M#>�JIzyPO��aLKcX�XQ�Wt���c�f^�^x`�RR�(~`�ȃ ��9���
�F�>؃�XTX��r����N�r��_�NI��#,0)������x�&��[as;I W�I�ƣgz�9nh���1�������p3t͌��пv�L�	W����j6�:��F�z�«I���<��l��f�~[&�6�Tݚ�hq>`�'�x�I��H�Z�XTW��C���;g~]ď�e���lS��F�8��+MN}��~7i���U��7�k���z�[��WIs�i'�aޝ �^�:Tg�͛y.`g�N|�������������iR�qx�����b�2����"�L�F<
\o��!m��r^�9��V]&�hK!�����`0ņ�|��+���
�ˑ ��W��Dmg�?*��o%r������T�ė���T!	eOawm��Đ%��JT!�,��j�v�X�4f�<*��T�\0+��Gݓ��8�ϸ��6��vRѩ���)�'��M�@���Пy�v�&�G@N�=SS� �u�)8+�!Cu�d������d�)�3b�m��4�W�A�H����RI��X@�F13�N%d��(')VܼSAi�CM#�>x'
����� U�D��qR:wn�|f�
�ذ�S�bF��eHi�N��n�(y$�X�bT�ke=��4#�SP8�2+�D��+�&�2�|��Oʼ�+�'��.Be��辡`@���(C%ri�\֠ebH�0�=k�-�V7eK�dE+ۜ�L�aue�煐��j�������cl<���H�/W���@�����d}��E� TPNR['õ�ك|[E)Ӓ�B����D�4�g"t�˄nI�2M�4K��v&�Y�'��[����;c�����(oe����P*�xl��r�V��p��� �f匽�3w����J�G��+'�.f:�\a���=��}"���T�hC�*XzV�h.bV��C�� ��T��s�QƷ��Kv�m���Є�*Ϊ-8��	�#�������HcŘ�nf8���%����d�ScJѕڀ�m�l�w�m%h����d%I!y<G���h���Ɉ���ݔs\�A'��o�Q$�o�چ�N�X��M�|��֍��s<_PG�=��[���\.����a����O�X�ˌ��l���}�c�1wi�{ytx48:��m0`B��W��\$��~f!�2�����ϊ�y���`4
 %kb1lB�J���.a����ě�*a�ܝ�1p��=xP	��]#p�zm�be�"�>��|zYF�ն�c:pS��0|ex��\7�uen� rI�~�^����ʫ �!U�{�E���]�i�y u���w��{Q?TèQ�����G?����B���?Ǎ��Ȼ ��d�,V���ٷ�v<��9FԒ v@�ϭ��r��L�n(~/��̐\]ϟ�1�ۉg{8���)Ib5�g���M!Gj�v�Q�/��;����~�d��/}�X?W�S?�}�!�Ԟ3�\�i<~��P8�����jD&���%�"�c�(������j^���Z@k >�$���j#��*�X�R��B�y��xU&ۚ����V���N����}���M���n��J��:��n=��N��6Wڛ���)=:�'����d�6>:O7��^[���VZ �<����d����'��@�ݕ�'�X�6A�o>��z�� ���_q%(�J�UY"�����I��3tJ8�aЭ�g��z=���V's5��p�nRЕ'�ڥ<x|G�KN���4�rr��Z�dUH3C=ݚxD��������:�{�t��=6q�J�l���k71���gu�4�+�8�����С�f���:=�r G�;���O�~���8����v�4N:g��7�fX���x!�9>���%&ՠ�c��r��g����e���ճt�hK8|�o�@�έX{B���W��;v�'���ܢ���,ܛ����mä_�����I�L�ɮ&F��!���=k����;V��k΅�@"���J�l��[�K��h(!������-P��&�ֿ���?�����ϻ�cA�_wc��?��n|���*�,�/9&�
�� �*�ӵ��%���XB��v��pp|@�A6`�ӹ��N��"��1d�	�ͯŗd�+� ,-�����Ï�����!�9��|�\�U��b�=~E�T�Ӭ��!�خ��R�N{q-'�m0��;	H�y$�d����r*QW�]��ڮƚG�x߰s[��T�E���HU$T��kd�_ߚ�l�T��#I:QK�E��H�?��X&�(X�J���Vc9'3.(�$7ZE]�NDK��{	3_N�	}���I�7E)�ȟE�Ԛ��rJSj�s$T�"��/\�Į7����I��@jD%éD���Ƙ�^�3�7�ٮ �o��j�l��$,0ò�W}�����2�O{M��M���Z���������|z��ẋ��|�Q̧~c+t������ԁ߳�q���s���{?�W�9��^:C����w�=��x��d��/��g&�4޺�ȿ���A�m���%~ImF��Ȫ�����j`�W�{*Ro�c����w����\���)	,� �3�:~T�~������O�#�#�w �ि�n�&y,6�>���̝�%sKf�j4��u�ޒk�x��{
o':P����D��Z�{�C���0������1t��k�o�ƞ^�^3{[�r!�����Ϗ{���o�r�����	�_��b���Go^��{�V�I��AqQ�ھ�M�����N���-�������{�����T��5��ug�r���S�=�/�FfnLZx�8�	����	�T�ܵ3��(���E��!��Z�y���
C74:�l����^:�m��<\�A�m4NDf=�Mb&:<d�۱e���պ^�W���j��{��6nd�=_ѲMʼH�/{ĕE�m�-�$o��kD���9�)'��1y��T�S�|�~�t7� ��Pf�����%�`�F��t7p�t��
�H�OY�z�~g��דk�\k�ߌ{F����u�i��ͯ�;P���Ȏ���\H��tZĨ�9% T>L�����n~�����b�i��UD=����V=�
E�a��_�+kY�Ğ�N^C����~-N����L~��;�w�6VD�e��)�@�x�1�be�
���W���uC�Za�j&81��=N�p��Y\'�l���_su����t���#'o� ��vQɳY�E��|�����Ǐe��=^{�����bxKV���b������m���9J���T܇.�*X\5��Cm+��ͯ{�_�EKX#���*��n���b!b+
X	?��1��"�?�bX�ӧ�E2"JA*^u�>�b��Ĺ���Z��I��i(���i�aiV**!�(}�(V�� �wj�%�sHd�3��G�Q�j���'CO8��UU��M�U4t-u)�����3��ǿ(P�H��hq"� ��t���H&}��ԛ��DLе��/���"9�����;_Sl�.L��v�R����{
�g=��`�����$����y���)9,i��6�v�����jx��?���8�`{�<���VR;e���aR[(�+M�� �)݀_R)`���ɧ#	<<����m�����{�_n���� �dG�֙�Q:��T��ѯ"���%�T�T�V�\�;7�Q䝁�q'&fޕ�Z��VJ���{B��mi׍V�Zbk`e��eM���Cd}��M��ۦԁZ&Q�$��Opɏv�I��L��u�!ƉSN��l�~D ����d�a�69}[:1c��~�~��;�D�J����4��1����R$s��S�H�i%m���zVa,%�A"HS���[�@�J�.��;E���9�3�F5\��n$$#)T}������3w�(�\�MY���6��,z��E\��h��I�"�G�ǳ�̉2j��
V3���y�^q$
�Uqh��Ϝ{3KOs�<�*dՂ �yԄt��K��tW���<��J�����C`P�+R%��B��ҒQ���85o�ILSa�M3aQ�~shI�0����Ռ�Ծ�	�?�bvO�Սɪ}���PI*!���� ����^�Jr����a����RӀt��!��@���1VR���aV��~\ʵ��mS���2R�ɽ�Pf_O��&�.Q?.�./E
��Jz�k�4��zt3�P��ݪ�D)��W�+6Q�WQ��V�qm5�b�a�v�DZ ]Ky�E˶*V6ma�YW�b`Y)_X�"^��� ���Ae��tع��L�(r�W�2��;�VD�br:�����W��U˕��Ê��Ĩ�P��d
 ��w�%�B#Fu�F�#��F�M��I���yֳ����?aE�|Е��XE�qF��~X{!�g��ADz�����^5������g�8�a����ef�������w������-@Q�Sr_	܊�`G����y^p�7B�p���(d$k���~�Oӫ�BLS���gbĚ\J).�YR�]�=7��6�d7�޺t��I#�{}���ގh���Ӯ���]�U��*�rh��T�K0��G��LH�R��2 �'D]>n��&�q�L����e�H��@�O��@�r�IT˂���>��|���5'�'�f����Kf�-Y�e�j��s߼�B,ʁ�@+����L�	�rj�)`����	ݟ�,�>�JB�Ҵ���cS�М��M!�n��~��-���r��2W��ē��>�V +-s~���nW��-�a��M0���k�'n��������ãݿ��9*ay���X`tW`#�I�v��h���ģ���dOFxK���������*�D�Pu��-5�F-N����7����
������[��<~a�����j��tm����\�2�G�Uh�L5o7J������tv1ڄ�GB����wN.�^����Y���j����/~�i�"��e�3�0��yDXƇ$�fA�|��,2�2U�D�j��e噎���1��w`�T5�.ͽ�����娽���t\�,�t�-�?fe3W�<"U\*R�J��V�$#a���*�
�h��_��E e�MC�V�/f�.veQ+/�5!���[�z��&�O������ԍ�p�ޔ�M�p��N�9��Ŷ̳�U���R�Ujf� �?+a�DY�c2`T2�J�R��؋�`w��x�H�`��YPY��#�i�=�����BȦU�)M�?|#������Z���d���t��U>�d���ҙV'D
��u��%�$;�O�E=�e������#GKF����A���q%x[���M��(;~r1��q��'{
�惖���qb����=ρ����JK�1��V,	M��c�%��ǘ�*>oa���Iؒav�+�Pt�HqH}	h7Dzmmϼ�$�+�����6?�1�,k��Wş�޽�^�MF+v�m1v��U��;{��+ڒ�AY���Ҭ��Y��W�nM�23��O�^�_�y�(X�r}vR6��1���������BG��?A��D{��Cr\We؋x�6U?>W�$�Zآ<��k�����
���K��~,��h)9l1; +s�s=�,��VaY��j��RI̓��l��$��L�D�ٛ5/m�P2��[Uu���֫�q�����L����O��SH+uLM�Ҁw�7����q���7�K�m˷��$O��C��	K�IX
�Z���,n�uUH�B��k�w.٨�����q�.�ږ��R���x��_:%���*a\9Uy��G�nA���э)~�\�(>y���6�JH��G_�t���D�L��HW�vj�e/���@�l8ff��: y� {���K��oʷ����@x �W�E�D_3���l���ʀ��v����4ߊ��d�ky7�l� S`�t����2����Z�d��;�k�S��d,W{m1��c���Лx��}#����a֫�����j'��K�n���Ss'��{joWΙf6�����-c�;7l5�!|�&�,W����P�~�(5�4&���=庖�C׼�V���D��-��V��yJ�s��0��k���� ��RN/����D��̠�#���,�^e5���z�ʻw��b�`��E鮻q��r�~��pتΪ�Aajk�p���W�8��$U�ظ4zkf&���f���*���e�6��K7ǆ��*7zl�@���
/�J�0: nIdB����7��S��0e��Qx��h����N"���/ z�Tk�6O�T�;2�2�ݓ��X�l*/nK�D50Mk��L���P6�~�O6bm��+Q�f�GG��<��h�?�t̄���b%>�Li�e��%�JD���'�~J�8^�wV
|2'hq~���`fv0?%n�.�zo�1��fiF}�L�YY�Tn�{G�j�@Ց��J��g4W�@P�`����2�R�^����c�ƺ�=�#o�M(p�o�*w���İEdM�P�S��X�u[�@s�P8�~���Dl�r$M���L]����9}�^$��l��eYw&�G��c�#A��
��J���@V�dn�J;�-V9N���W���_�N�l��#�{_	w"��9��8o���ߙ��$�����<��l��!P5�e��ʛo��3���}�*��!l�0d�p�QO�z	v[M�VjϨ�$'�F�I ���c��Â��������h("j`�!��LQq��ן���3��k�L��Jni�pJ�Tac<�w�v%��v9��f�k悩ș����?$�f�̋O�pX]��j���U\�Rl�x�������d��G�u:tqΈ�,�ȭ)	gc��L>U�2�	�s�F�1C����盻�����n3�`~V��,� �tX�<3���;��bo4��\w�4\�"@c#oH�,�Y3��\�|ޑc9�'�9��`�Kǚ��im��>{>.��)C[��$)���㉺�yV��\i#n��w���3�`�'��܏Q._�c��C�&�o��+o 컪	�rNr��\�Q.��D�]��9�oj���TH��G;��t�8��h�������j��W��%�M.bʲ�^;9��gG����w� 
��O�(���b!��aT-���N(A	?v�6ü%�w8�T�ޔ���,rU��Q��fړ�U��3@�<�Ґ��~�g���	��!�3�sډj9�v�|�'"AM`I���?5��d��1m!&	�:�J���\sP�Aȉ�"�7���U|��`v_�8��!ҎO�o��
�sE�h�����6���ڛ�Xo���-�V,>��e]��}X_�2�?"��������˴��]�,8e;U�<Ǣ�~�X������ʂ�������=X@if�$�z���BU�X��*��ʞ�rY����/�z�_z��\�(��wu�y���Ǐ���D����y���A��Z�ʾ�Rp�_޽b<���I��/,)��ޛJ���I��Bi�qC����>)V9��l�V�BMb����T�*��0�������;{u@tp��X���+(��; �)m���ܷ���.nlq�Ew'�X���e��
&�fˈ��=���+��(���л
*C���\T��d ��+zu��k�!ae}��~��Yg�e-ʗPDY�ɼ+c�9<ۥ���ɔ��>7 �����?ʬ�O���H)��W����W��c��h|�R�1�"��Jjm�z�]tF����0�n�;k��U�pɑ��We�kIVg�#OR�O�v���ơ]��.��I��I2&�]ڶ�-y���Y;~��sZOA�H�g�c��]x+u�&[m�9�::�}��?�ͭ�j@���z�M�ϳ[���AJo���kĬ��~�׆Ǫ�9�V��2�V��:�a�*Y�1;uB�����xCQ�O��h��:u��h�ƨ�¡��z6�4���h4���Es,�P$���^��1;,|�'�rT��d��/��_V�u���kV��˘J<���|cE�k��+�!�.�p#��,u���s�H��l�TA�����#��{��S/G<�_��2{%V�]�$��O2j��F��9�{/�J���fX{O��F���������wŦ�#'��(���_���0���d1�7RRe_�_[�O8)�B�@�q�˧@���XΆ�;��Ci:����7�!�&O�K'���vz]P1�Nfr�M�Z��<���:v8��r2el��2����e�O�@�pz2��Y�pyn)�p��D�Q��W\?�n2�u�՚�"!�F��rŷ��e��ŵ��坎��F�� 	)�l���w.��]�0�V��-QZ����E8�����.�����B��^|�|c�� 	۩�D��b��W>��5���t�e�$Œɞ �x���C�1�r��Y��v<�S���"��ѣ�����'������b���r{�s�:'n|��l��럇-)��*�Gl���M<��@�'�#+vAZ% a+p�x�c�m�������M�������茦�!~��f[a�]�˥�/�q���gP�d��{�V髱�����q�����%�{����^a�6T��볱U@���c����7>������%V�=�0e]٣Fo�A�@�R�@�	�b����Z��c[uN}<�a�~�����Z�#���{���{ВÍVt��WH��J���uV�&�߱��-�<�l9AP���������~8Lh�S&�Ïo۝���jv�j�no,/����3O}O�2�e��l��*��22KǘС�j`�8U��_6��P?G���#i�ݨa�F��Vc߱r��߮��2G�C���Lu�	C�"���o�L恺1q*��?���6B���)�������B��H�Q��qX�߯��_.��o�x���>y������b��D�z����hCnΰ�v�`�h���V�h�����ƃ��?���k����*k��AAy�d����Q���_��{���-3���i�bB�wކ;Dx���h:W�8����x8�����~	/�s�w����9�@]j'F�o0����{х��cF��S׏��s�_�����=�6��� Ĭp�f{^py�؃�h���`:p�lB��oh��G (������P�\�B�ۈ�G�0�S�z�`e{1���Ϸ�u��oW��#�?\�K<|��YQ��(�:����9�]*����!���x:��r�7���d2^�t�v�Zq�4@{�M:cw�;�����A˝N�ܨ�S��y���~��@���c��[/_n���;���Agy�}<�C�wG��t�QW�f����!-`��&�ù�hc�� ��h �|������94��C����/j���l��M$�8rG1�����%���eyC�Xxg�>[� �Y2|8���r��X����7�0������M��pLdGEPw1�u:2v'��$��;�5o�N;�E_u�_��.`��q�����g�#�#���pJM9����Y��b�1[��Xn�6xO���@�6@iɒ�]�~��(�>w0�E�`��"�A/׷�����q+�ފ�� ��tso��WH��q�L�F�W�݋;��}���Z�sO{\k���F�!z��_Ht�+_���@����/���~u�y�{����������;}w��AYC�B�_�p�h�H�;�S�G��9U|�}����h���s���i�t��G8\��`��F^�1�̰㝭��޾����`��=xzw�W���Fo��s�����6�J�F��٭t��N|7�\�\��d�a����%�j]��W�k�9��-�t�D8O&�9| �|�v�-ud ~��|���l�ۨ��j�l�h�X�bI��.f�
��K$�#9+{��q$���:��gG=��4���ɠw�Ǵ	#v�1�����F<Sl"T��OJeߥ�C#A����o1�N�������c3j+�c����!�$��u������ew��[;�'�Fҿ���óu�		�	A#Mz2c���k]��C�F;L�����RE5.�B����L�� E4��P�J��uJ��n���'r�h�h�_r�n�:��3!�6��y���Z8��"���CDc�Ѫ��0~�+ֆ�9�W� ��7�?� ��zR�����w�	�0N�p����;2��0XxC�o9�7���y���������2̺��F� ��b�w�ّ����&��͗_�nn�p�-a�}f��ge�P�&�C�I�<F�����V�1o^�SP�j���8��U�n�l	��Oٷέ[Y��m5���҆Uo���\G9�����=�)������_��1l���X"p� ~oцo+;�vn�cE�K'o�I8y��N裫_Q���K�0�P��:�V/�H��_'�8�EHz�q��Bt�'r�r^e��S9O����}��LS�59�����'�Lo�(b)#�s�,��5������^�&]l	�[g�~9�0ce#@��Q_�+ylO�0MG���{�&4��K"F�!-�_AbZiR:9�j��������������~�6/���������OB�R�e�{�A9�'>�ٷ5t@$ݰ>YC'��&kCi������:�,E�W�$��ot��5Z���`�D�a��}��H���p�Q�� u6
VS �KԅH	v^p������2���b��k, ؞y�6�{>�68�M��l$�v�κ�{b%��(2Ӎ��.�&�&�>׍��;[������u�9�l9����5���|�I�X�TG����� dJ�G?�݆�0Fn�F���#����]�����{��+F ����~Ң,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ�L�EF�x @ 